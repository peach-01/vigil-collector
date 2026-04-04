import 'dart:async';
import '../data/sensor_packet.dart';
import 'wearable_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class MockWearableService implements WearableService {
    final _controller = StreamController<SensorPacket>.broadcast();
    Timer? _timer;
    
    // Fake ID for web/testing
    @override
    String get deviceId => "MOCK-DEVICE-ID-123";

    @override
    Stream<SensorPacket> get stream => _controller.stream;

    @override
    Future<bool> connect() async {
        _timer = Timer.periodic(const Duration(seconds: 2), (_) {
            _controller.add(
                SensorPacket(
                    heartRate: 60 + (10 * (DateTime.now().second % 3)),
                    hrv: 42,
                    temp: 36.8,
                    motion: 1.2,
                    sleepQuality: 80,
                    sleepTime: 7.5,
                ),
            );
        });
        return true;
    }

    @override
    Future<void> disconnect() async {
        _timer?.cancel();
    }

    @override
    Future<void> connectToDevice(BluetoothDevice device) async {
      // mock implementation
    }

    @override
    Stream<List<ScanResult>> get scanStream => Stream.value([]);

    @override
    Future<void> startScan() async {
      // mock implementation
    }

    @override
    Future<void> stopScan() async {
      // mock implementation
    }

    @override
  Future<bool> reconnectLastDevice() {
    // TODO: implement reconnectLastDevice
    throw UnimplementedError();
  }
}