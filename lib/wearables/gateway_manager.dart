import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vigil_collector/data/data_pipeline.dart';
import 'package:vigil_collector/data/uploader.dart';
import 'package:vigil_collector/wearables/ble_service.dart';
import 'package:vigil_collector/wearables/wearable_manager.dart';

class GatewayManager {
  final Map<String, WearableManager> devices = {};
  final FirestoreUploader uploader;
  final String orgId;

  GatewayManager({required this.uploader, required this.orgId});

  Future<void> addDevice(BluetoothDevice device) async {
    final ble = BleWearableService();
    final manager = WearableManager(ble);

    await manager.connectToDevice(device);

    final wid = ble.deviceId;
    devices[wid] = manager;

    final pipeline = DataPipeline(uploader: uploader, ownerId: orgId, wid: wid);
    manager.data.listen((packet) {
      pipeline.add(packet);
    });
  }

  List<String> get connectedIds => devices.keys.toList();
}