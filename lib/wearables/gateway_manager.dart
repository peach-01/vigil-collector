import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vigil_collector/data/data_pipeline.dart';
import 'package:vigil_collector/data/device_info.dart';
import 'package:vigil_collector/data/uploader.dart';
import 'package:vigil_collector/logger.dart';
import 'package:vigil_collector/wearables/ble_service.dart';
import 'package:vigil_collector/wearables/wearable_manager.dart';

class GatewayManager {
  final Map<String, GatewayDevice> devices = {};
  final FirestoreUploader uploader;
  final String orgId;

  GatewayManager({required this.uploader, required this.orgId});

  Future<void> addDevice(BluetoothDevice device) async {
    final ble = BleWearableService();
    final manager = WearableManager(ble);

    await manager.connectToDevice(device);

    final wid = ble.deviceId;
    if (wid == "unknown_device") return;

    final pipeline = DataPipeline(uploader: uploader, ownerId: orgId, wid: wid, isOrg: true);
    final gatewayDevice = GatewayDevice(manager: manager, pipeline: pipeline);

    devices[wid] = gatewayDevice;

    manager.state.listen((state) {
      gatewayDevice.state = state;
    });
    
    manager.data.listen((packet) {
      gatewayDevice.lastPacket = packet;
      gatewayDevice.lastUpload = DateTime.now();
      pipeline.add(packet);
    });

    await _fetchAssignedUser(wid, gatewayDevice);
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

  List<GatewayDevice> get allDevices => devices.values.toList();
}