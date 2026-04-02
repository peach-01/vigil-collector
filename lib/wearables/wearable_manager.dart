import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vigil_collector/data/sensor_packet.dart';
import 'package:vigil_collector/logger.dart';
import 'package:vigil_collector/wearables/wearable_service.dart';

enum WearableState {
  idle,
  scanning,
  connecting,
  connected,
  streaming,
  timeout,
  notFound,
  error,
}

class WearableManager {
  final WearableService ble;

  final _state = StreamController<WearableState>.broadcast();
  final _data = StreamController<SensorPacket>.broadcast();
  final _devices = StreamController<List<ScanResult>>.broadcast();

  StreamSubscription? _dataSub;
  StreamSubscription? _scanSub;

  Timer? _watchDog;
  Timer? _scanTimeout;

  DateTime _lastDataTime = DateTime.now();

  bool _busy = false;

  WearableManager(this.ble);

  Stream<WearableState> get state => _state.stream;
  Stream<SensorPacket> get data => _data.stream;
  Stream<List<ScanResult>> get devices => _devices.stream;

  // ----------- CONNECTION FLOW ------------

  Future<void> connect() async {
    if (_busy) return;
    _busy = true;

    final success = await ble.connect();
    if (success) {
      _onConnected();
    } else {
      await startScan();
    }

    _busy = false;
  }

  // ----------- SCAN ------------

  Future<void> startScan() async {
    await ble.disconnect();
    await Future.delayed(Duration(milliseconds: 500));

    _state.add(WearableState.scanning);
    await ble.startScan();

    _scanSub?.cancel();
    _scanSub = ble.scanStream.listen((results) {
      _devices.add(results);
      if (results.isEmpty) return;

      // auto-connect future logic
    });

    _scanTimeout = Timer(const Duration(seconds: 12), () {
      _state.add(WearableState.notFound);
    });
  }

  // ----------- CONNECT ------------

  Future<void> connectToDevice(BluetoothDevice device) async {
    _scanTimeout?.cancel();

    if (_busy || ble.deviceId != "unknown_device") return;
    _busy = true;

    _state.add(WearableState.connecting);

    await ble.connectToDevice(device);
    _onConnected();

    _busy = false;
  }

  void _onConnected() async {
    await ble.stopScan();

    _state.add(WearableState.connected);
    _listenToData();

    Future.delayed(const Duration(seconds: 5), () {
      _startWatchDog();
    });
  }

  // ----------- DATA ------------

  void _listenToData() {
    _dataSub?.cancel();

    _dataSub = ble.stream.listen((packet) {
      _lastDataTime = DateTime.now();
      _data.add(packet);
      if (_state.hasListener) _state.add(WearableState.streaming);
    });
  }

  // ----------- WATCHDOG ------------

  void _startWatchDog() {
    _watchDog?.cancel();
    

    _watchDog = Timer.periodic(const Duration(seconds: 5), (_) {
      final now = DateTime.now();
      if (now.difference(_lastDataTime) > const Duration(seconds: 40)) {
        logStep("WATCHDOG", "Timeout - no data");
        _state.add(WearableState.timeout);
      }
    });
  }

  // ----------- RECONNECT ------------

  Future<void> reconnect() async {
    if (_busy) {
      await ble.disconnect();
    }

    _busy = true;

    try {
      _state.add(WearableState.connecting);

      await ble.disconnect();
      await Future.delayed(const Duration(seconds: 1));
      
      await connect();
    } catch (e) {
      _state.add(WearableState.error);
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() async {
    await _dataSub?.cancel();
    await _scanSub?.cancel();
    _watchDog?.cancel();
  }
}