import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vigil_collector/data/data_pipeline.dart';
import 'package:vigil_collector/data/gateway_device.dart';
import 'package:vigil_collector/data/uploader.dart';
import 'package:vigil_collector/logger.dart';
import 'package:vigil_collector/wearables/ble_service.dart';
import 'package:vigil_collector/wearables/wearable_manager.dart';

class GatewayManager {
  final Map<String, GatewayDevice> devices = {};
  final FirestoreUploader uploader;
  final String orgId;

  final StreamController<void> _update = StreamController.broadcast();
  final Map<String, List<StreamSubscription>> _subs = {};
  final Map<String, Timer> _rssiTimers = {};

  bool _isShuttingDown = false;

  Stream<void> get updates => _update.stream;

  GatewayManager({required this.uploader, required this.orgId});

  Future<void> addDevice(BluetoothDevice device) async {
    if (_isShuttingDown) return;

    final ble = BleWearableService();
    final manager = WearableManager(ble);

    await manager.connectToDevice(device);
    await Future.delayed(const Duration(milliseconds: 500));

    final wid = ble.deviceId;
    if (wid == "unknown_device") return;
    if (devices.containsKey(wid)) return;

    final pipeline = DataPipeline(uploader: uploader, ownerId: orgId, wid: wid, isOrg: true);
    final gatewayDevice = GatewayDevice(manager: manager, pipeline: pipeline, connectedAt: DateTime.now());

    devices[wid] = gatewayDevice;

    // ---------------- STATE ----------------
    final subs = <StreamSubscription>[];

    subs.add(manager.state.listen((state) {
      if (_isShuttingDown) return;

      gatewayDevice.state = state;

      if (state != WearableState.connected) {
        gatewayDevice.statusNote = "Disconnected";
      } else {
        gatewayDevice.statusNote = null;
      }
      _update.add(null);
    }));
    
    // ---------------- DATA ----------------
    subs.add(manager.data.listen((packet) {
      if (_isShuttingDown) return;

      gatewayDevice.lastPacket = packet;
      gatewayDevice.lastUpload = DateTime.now();
      gatewayDevice.lastSeen = DateTime.now();

      pipeline.add(packet);
      _update.add(null);  // UI refresh
    }));

    _subs[wid] = subs;

    // ---------------- RSSI (periodic) ----------------
    _startTrackingRssi(device, gatewayDevice, wid);

    await _fetchAssignedUser(wid, gatewayDevice);
  }


  Future<void> disconnectDevice(String wid) async {
    final device = devices[wid];
    if (device == null) return;

    try {
      await device.manager.ble.disconnect();
      device.statusNote = "Manually disconnected";
    } catch (e) {
      logStep("GATEWAY", "Disconnect FAIL: $e");
    }

    devices.remove(wid);
    _update.add(null);
  }

  Future<void> _fetchAssignedUser(String wid, GatewayDevice device) async {
    try {
      final db = FirebaseFirestore.instance;

      final wearableDoc = await db.collection('wearables').doc(wid).get();
      final uid = wearableDoc.data()?["assignedTo"] as String?;

      if (uid == null) return;
      
      final userDoc = await db.collection("users").doc(uid).get();
      final userName = userDoc.data()?["profile"]["name"] ?? "Unknown User";
      
      device.assignedUserName = userName ?? uid;
    } catch (e) {
      logStep("GATEWAY", "Fetch user FAIL: $e");
    }
  }

  void _startTrackingRssi(BluetoothDevice device, GatewayDevice d, String wid) {
    final timer = Timer.periodic(const Duration(seconds: 5), (t) async {
      if (_isShuttingDown || !devices.containsValue(d)) {
        t.cancel();
        return;
      }

      try {
        final rssi = await device.readRssi();
        d.rssi = rssi;
        d.lastSeen = DateTime.now();
        _update.add(null);
      } catch (_) {
        t.cancel();
      }
    });

    _rssiTimers[wid] = timer;
  }

  Future<void> dispose() async {
    _isShuttingDown = true;

    for (final entry in devices.entries) {
      final wid = entry.key;
      final d = entry.value;

      try {
        for (final sub in _subs[wid] ?? []) {
          await sub.cancel(); // cancel streams
        }

        _rssiTimers[wid]?.cancel();   // cancel timers
        d.pipeline.dispose();   // stop pipeline before disconnect
        await d.manager.ble.disconnect();
      } catch (_) {}
    }

    _subs.clear();
    _rssiTimers.clear();
    devices.clear();

    await _update.close();
  }

  List<GatewayDevice> get allDevices => devices.values.toList();
}