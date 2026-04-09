import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vigil_collector/data/data_pipeline.dart';
import 'package:vigil_collector/data/sensor_packet.dart';
import 'package:vigil_collector/wearables/wearable_manager.dart';

class DeviceInfo {
  final BluetoothDevice device;
  String? userName;
  bool isConnected;

  DeviceInfo({
    required this.device,
    this.userName,
    this.isConnected = false,
  });

  // add more properties later (battery, signal strength, etc)
}

class GatewayDevice {
  final WearableManager manager;
  final DataPipeline pipeline;

  SensorPacket? lastPacket;
  DateTime? lastUpload;
  WearableState state;

  String? assignedUserName;

  GatewayDevice({required this.manager, required this.pipeline, this.state = WearableState.scanning});
}