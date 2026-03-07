import '../data/sensor_packet.dart';

abstract class WearableService {
    String get deviceId;
    
    Future<void> connect();
    Future<void> disconnect();
    Stream<SensorPacket> get stream;
}