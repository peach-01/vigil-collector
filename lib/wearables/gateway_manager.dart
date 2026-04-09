import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vigil_collector/data/data_pipeline.dart';
import 'package:vigil_collector/data/device_info.dart';
import 'package:vigil_collector/data/uploader.dart';
import 'package:vigil_collector/logger.dart';
import 'package:vigil_collector/wearables/ble_service.dart';
import 'package:vigil_collector/wearables/wearable_manager.dart';

class GatewayManager {
  final Map<String, DeviceInfo> devices = {};
  final FirestoreUploader uploader;
  final String orgId;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  GatewayManager({required this.uploader, required this.orgId});

  Future<void> addDevice(BluetoothDevice device) async {
    final ble = BleWearableService();
    final manager = WearableManager(ble);

    await manager.connectToDevice(device);

    final wid = ble.deviceId;
    if (!devices.containsKey(wid)) {
      devices[wid] = DeviceInfo(device: device);
    }

    final deviceInfo = devices[wid];
    deviceInfo?.isConnected = true;

    final pipeline = DataPipeline(uploader: uploader, ownerId: orgId, wid: wid);
    manager.data.listen((packet) {
      pipeline.add(packet);
    });

    await _fetchAssignedUser(wid);
  }

  Future<void> _fetchAssignedUser(String wid) async {
    try {
      final wDoc = await firestore.collection('wearables').doc(wid).get();
      final assignedTo = wDoc.data()?["assignedTo"] as String?;

      if (assignedTo != null) {
        final userDoc = await firestore.collection("users").doc(assignedTo).get();
        final userName = userDoc.data()?["profile"]["name"] ?? "Unknown User";
        if (userName != null) {
          devices[wid]?.userName = userName; // store name for future use
        }
      }
    } catch (e) {
      logStep("GATEWAY", "Fetch user FAIL: $e");
    }
  }

  List<String> get connectedIds => devices.keys.toList();
}