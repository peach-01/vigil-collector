import 'dart:async';
import '../data/sensor_packet.dart';
import 'wearable_service.dart';

class MockWearableService implements WearableService {
    final _controller = StreamController<SensorPacket>.broadcast();
    Timer? _timer;
    
    // Fake ID for web/testing
    @override
    String get deviceId => "MOCK-DEVICE-ID-123";

    @override
    Stream<SensorPacket> get stream => _controller.stream;

    @override
    Future<void> connect() async {
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
    }

    @override
    Future<void> disconnect() async {
        _timer?.cancel();
    }
}