import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../data/sensor_packet.dart';

abstract class WearableService {
    String get deviceId;
    
    Future<bool> connect();
    Future<void> connectToDevice(BluetoothDevice device);
    Future<void> disconnect();
    Future<void> startScan();
    Future<void> stopScan();
    
    Stream<SensorPacket> get stream;
    Stream<List<ScanResult>> get scanStream;
}