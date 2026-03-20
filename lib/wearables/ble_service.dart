import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vigil_collector/data/wearable_storage.dart';
import 'package:vigil_collector/logger.dart';
import '../data/sensor_packet.dart';
import 'wearable_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

const String G69_UART_SERVICE = "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E";
const String G69_UART_RX = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
const String G69_UART_TX = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

class BleWearableService implements WearableService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;

  @override
  String get deviceId => _device?.remoteId.str ?? "unknown_device";

  final _controller = StreamController<SensorPacket>.broadcast();
  final List<int> _buffer = [];

  // last known values
  double _hr = 0;
  double _motion = 0;
  double _temp = 0;
  double _sleepQuality = 0;
  double _sleepTime = 0;

  @override
  Stream<SensorPacket> get stream => _controller.stream;

  @override
  Future<void> connect() async {
    logStep("BLE", "CONNECT START");

    if (kIsWeb) {
        throw UnsupportedError("BLE wearables are not supported on Web. Please use the mobile Collector app.");
    }

    final savedId = await WearableStorage.load();

    // STEP 1: try reconnect
    if (savedId != null) {
      logStep("BLE", "Trying auto-reconnect to $savedId");
      final device = BluetoothDevice.fromId(savedId);

      try {
        _device = device;
        await _device!.connect(timeout: const Duration(seconds: 5), license: License.free);
        logStep("BLE", "Auto-reconnect SUCCESS");

        await _discoverServices();
        await _startStreaming();
        return;
      } catch (e) {
        logStep("BLE", "Auto-reconnect FAILED -> scanning fallback");
      }
    }

    // STEP 2: scan (1st time pairing)
    await _scanAndConnect();
  }

  Future<void> _scanAndConnect() async {
    logStep("BLE", "Starting scan...");
    
    BluetoothDevice? found;

    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        logStep("BLE", "Device: ${r.device.name}");

        if (_isVigilWearable(r.device)) {
          found = r.device;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    await Future.delayed(const Duration(seconds: 10));

    await FlutterBluePlus.stopScan();
    await sub.cancel();

    if (found == null) {
      throw Exception("No Vigil wearable found");
    }

    _device = found!;

    logStep("BLE", "Connecting to ${_device!.remoteId}");
    await _device!.connect(license: License.free);
    logStep("BLE", "Connected!");

    await WearableStorage.save(_device!.remoteId.str);

    await _discoverServices();
    await _startStreaming();

    _device!.connectionState.listen((state) async {
      logStep("BLE", "Connection state: $state");

      if (state == BluetoothConnectionState.disconnected) {
        logStep("BLE", "Device disconnected -> retrying...");

        await Future.delayed(const Duration(seconds: 2));
        connect();  // auto-reconnect
      }
    });
  }
    

  bool _isVigilWearable(BluetoothDevice device) {
    final name = device.name.toUpperCase();
    return name.contains("G69") || name.contains("VIGIL");
  }

  Future<void> _discoverServices() async {
    logStep("BLE", "Discovering services...");

    final services = await _device!.discoverServices();
    for (final s in services) {
      logStep("BLE", "Service: ${s.uuid}");

      if (s.uuid.toString().toUpperCase() == G69_UART_SERVICE) {
        for (final c in s.characteristics) {
          logStep("BLE", "Characteristic: ${c.uuid}");
          
          final uuid = c.uuid.toString().toUpperCase();
          if (uuid == G69_UART_RX) _rx = c;
          if (uuid == G69_UART_TX) _tx = c;
        }
      }
    }

    if (_rx == null || _tx == null) {
      throw Exception("G69 UART characteristics not found");
    }

    await _tx!.setNotifyValue(true);
    _tx!.value.listen(_onNotify);
  }

  Future<void> _startStreaming() async {
    // Known G69 "start stream" command
    final cmd = Uint8List.fromList([0xA0, 0x01, 0x01, 0xAF]);
    await _rx!.write(cmd, withoutResponse: true);
  }

  Future<void> unpair() async {
    logStep("BLE", "UNPAIR");

    await disconnect();
    await WearableStorage.clear();
  }

  void _onNotify(List<int> data) {
    _buffer.addAll(data);

    while (_buffer.length >= 6) {
      final frame = _buffer.sublist(0, 6);
      _buffer.removeRange(0, 6);
      _parseFrame(frame);
    }
  }

  void _parseFrame(List<int> frame) {
    final type = frame[1];

    switch (type) {
      case 0x01: // Heart Rate
        _hr = frame[3].toDouble();
        break;
      case 0x02: // Motion
        _motion = frame[3].toDouble();
        break;
      case 0x03: // Temp
        _temp = frame[3] / 10.0;
        break;
      case 0x04: // Sleep
        _sleepQuality = frame[3].toDouble();
        _sleepTime = frame[4].toDouble();
        break;
    }

    _controller.add(
      SensorPacket(
        heartRate: _hr,
        hrv: 0,
        temp: _temp,
        motion: _motion,
        sleepQuality: _sleepQuality,
        sleepTime: _sleepTime,
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    await _device?.disconnect();
  }
}