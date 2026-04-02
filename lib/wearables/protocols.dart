import 'dart:async';
import 'package:vigil_collector/logger.dart';
import '../data/sensor_packet.dart';


abstract class BleProtocol {
  void onData(List<int> data, StreamController<SensorPacket> out);
}

class UnknownProtocol implements BleProtocol {
  @override
  void onData(List<int> data, StreamController<SensorPacket> out) {
    logStep("BLE", "RAW: $data");
  }
}

class VigilProtocol implements BleProtocol {
  final List<int> _buffer = [];

  @override
  void onData(List<int> data, StreamController<SensorPacket> out) {
    _buffer.addAll(data);

    while (_buffer.length >= 3) {
      if (_buffer[0] != 0x78) {
        _buffer.removeAt(0);
        continue;
      }

      final len = _buffer[1];
      final totalLen = len + 3;

      if (_buffer.length < totalLen) break;

      final frame = _buffer.sublist(0, totalLen);
      _buffer.removeRange(0, totalLen);

      _parseFrame(frame, out);
    }
  }

  void _parseFrame(List<int> frame, StreamController<SensorPacket> out) {
    if (frame.length < 6) return;

    final type = frame[3];

    double hr = 0, motion = 0, temp = 0, hrv = 0;

    switch (type) {
      case 0x07: // Heart Rate
      case 0x0B:  // Secondary HR? (resting/sleep)
        hr = frame[5].toDouble();
        break;

      case 0x0D: // Motion
        if (frame.length > 8) {
          motion = frame[8].toDouble();   // primary activity
        }
        break;

      case 0x03: // Temp
        temp = frame[5] / 10.0;
        break;

      case 0x15:  // HRV
        hrv = frame[5].toDouble();
        break;

      default:
        logStep("BLE", "UNKOWN TYPE: $type DATA: $frame");
    }

    logStep("BLE", "TYPE=$type VALUE=${frame[5]} FULL=$frame");
    out.add(SensorPacket(
      heartRate: hr, 
      hrv: hrv, 
      temp: temp, 
      motion: motion, 
      sleepQuality: 0, 
      sleepTime: 0
    ));
  }
}

class HeartRateProtocol implements BleProtocol {
  @override
  void onData(List<int> data, StreamController<SensorPacket> out) {
    if (data.isEmpty) return;

    final flags = data[0];
    final is16Bit = (flags & 0x01) != 0;

    int hr;

    if (is16Bit) {
      hr = data[1] | (data[2] << 8);
    } else {
      hr = data[1];
    }

    logStep("HR", "RAW HR: $data");
    out.add(SensorPacket(heartRate: hr.toDouble(), hrv: 0, temp: 0, motion: 0, sleepQuality: 0, sleepTime: 0));
  }
}