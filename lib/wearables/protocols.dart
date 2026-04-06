import 'dart:async';
import 'package:vigil_collector/logger.dart';
import '../data/sensor_packet.dart';
import 'package:flutter/foundation.dart';


abstract class BleProtocol {
  void onData(List<int> data, StreamController<SensorPacket> out);
}

class UnknownProtocol implements BleProtocol {
  @override
  void onData(List<int> data, StreamController<SensorPacket> out) {
    if (kDebugMode) logStep("BLE", "RAW: $data");
  }
}

class VigilProtocol implements BleProtocol {
  final List<int> _buffer = [];

  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastAbnormal = DateTime.fromMillisecondsSinceEpoch(0);

  Duration _currentInterval = const Duration(seconds: 10);

  @override
  void onData(List<int> data, StreamController<SensorPacket> out) {
    _buffer.addAll(data);

    while (_buffer.length >= 3) {
      if (_buffer.first != 0x78) {
        _buffer.removeAt(0);
        continue;
      }

      final len = _buffer[1];
      final totalLen = len + 3;

      if (_buffer.length < totalLen) break;

      final frame = List<int>.from(_buffer.take(totalLen));
      _buffer.removeRange(0, totalLen);

      _parseFrame(frame, out);
    }
  }

  void _parseFrame(List<int> frame, StreamController<SensorPacket> out) {
    if (frame.length < 6) return;

    final type = frame[3];
    final val = frame.length > 5 ? frame[5] : 0;

    double hr = 0, motion = 0, temp = 0, hrv = 0;

    switch (type) {
      case 0x07: // Heart Rate
      case 0x0B:  // Secondary HR? (resting/sleep)
        hr = val.toDouble();
        break;

      case 0x0D: // Motion
        if (frame.length > 8) {
          motion = frame[8].toDouble();   // primary activity
        }
        break;

      case 0x03: // Temp
        temp = val / 10.0;
        break;

      case 0x15:  // HRV
        hrv = val.toDouble();
        break;

      default:
        //if (kDebugMode) logStep("BLE", "UNKOWN TYPE: $type DATA: $frame");
        return;
    }

    final now = DateTime.now();
    _updateInterval(hr: hr, temp: temp, hrv: hrv, motion: motion);

    if (now.difference(_lastEmit) < _currentInterval) return;
    _lastEmit = now;

    //if (kDebugMode) logStep("BLE", "TYPE=$type VALUE=${frame[5]} FULL=$frame");
    out.add(SensorPacket(
      heartRate: hr, 
      hrv: hrv, 
      temp: temp, 
      motion: motion, 
      sleepQuality: 0, 
      sleepTime: 0
    ));
  }

  void _updateInterval({required double hr, required double temp, required double hrv, required double motion}) {
    final now = DateTime.now();
    final abnormal = _isAbnormal(hr: hr, temp: temp, hrv: hrv, motion: motion);
    if (abnormal) {
      _lastAbnormal = now;
    }

    final stillElevated = now.difference(_lastAbnormal) < Duration(seconds: 30);

    // fast mode vs normal mode
    _currentInterval = stillElevated ? const Duration(seconds: 2) : const Duration(seconds: 12);
  }
}

class HeartRateProtocol implements BleProtocol {
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastAbnormal = DateTime.fromMillisecondsSinceEpoch(0);

  Duration _currentInterval = const Duration(seconds: 10);

  @override
  void onData(List<int> data, StreamController<SensorPacket> out) {
    if (data.length < 2) return;
    int hr = 0;

    // try standard
    final flags = data[0];
    final is16Bit = (flags & 0x01) != 0;

    if (data.length <= 3) {
      hr = is16Bit ? (hr = data[1] | (data[2] << 8)) : data[1];
    } else {
      hr = data[1]; // fallback
    }

    final now = DateTime.now();
    _updateInterval(hr.toDouble());

    if (now.difference(_lastEmit) < _currentInterval) return;
    _lastEmit = now;

    if (kDebugMode) logStep("HR", "RAW HR: $data");
    out.add(SensorPacket(
      heartRate: hr.toDouble(), 
      hrv: 0, 
      temp: 0, 
      motion: 0, 
      sleepQuality: 0, 
      sleepTime: 0,
    ));
  }

  void _updateInterval(double hr) {
    final now = DateTime.now();
    final abnormal = (hr >= 120 || hr <= 45);
    if (abnormal) {
      _lastAbnormal = now;
    }

    final stillElevated = now.difference(_lastAbnormal) < Duration(seconds: 30);
    _currentInterval = stillElevated ? const Duration(seconds: 2) : const Duration(seconds: 12);
  }
}

bool _isAbnormal({required double hr, required double temp, required double hrv, required double motion}) {
  if (hr >= 120 || hr <= 45) return true;
  if (temp >= 38.0) return true;
  if (hrv > 0 && hrv < 20) return true;
  if (motion > 20) return true;   // adjust later based on scale

  return false;
}