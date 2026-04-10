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
  Stream<void> get updates => _update.stream;

  GatewayManager({required this.uploader, required this.orgId});

  Future<void> addDevice(BluetoothDevice device) async {
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
    manager.state.listen((state) {
      gatewayDevice.state = state;

      if (state != WearableState.connected) {
        gatewayDevice.statusNote = "Disconnected";
      } else {
        gatewayDevice.statusNote = null;
      }
      _update.add(null);
    });
    
    // ---------------- DATA ----------------
    manager.data.listen((packet) {
      gatewayDevice.lastPacket = packet;
      gatewayDevice.lastUpload = DateTime.now();
      gatewayDevice.lastSeen = DateTime.now();

      pipeline.add(packet);
      _update.add(null);  // UI refresh
    });

    // ---------------- RSSI (periodic) ----------------
    _startTrackingRssi(device, gatewayDevice);

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

  void _startTrackingRssi(BluetoothDevice device, GatewayDevice d) {
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!devices.containsValue(d)) {
        timer.cancel();
        return;
      }

      try {
        final rssi = await device.readRssi();
        d.rssi = rssi;
        d.lastSeen = DateTime.now();
        _update.add(null);
      } catch (_) {
        timer.cancel();
      }
    });
  }

  List<GatewayDevice> get allDevices => devices.values.toList();
}