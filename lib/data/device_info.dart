import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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