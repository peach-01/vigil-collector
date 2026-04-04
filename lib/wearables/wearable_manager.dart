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

  DateTime _lastDataTime = DateTime.now();
  bool _busy = false;

  WearableManager(this.ble);

  Stream<WearableState> get state => _state.stream;
  Stream<SensorPacket> get data => _data.stream;
  Stream<List<ScanResult>> get devices => _devices.stream;

  // ----------- CONNECT ------------

  Future<bool> connect() async {
    if (_busy) return false;
    _busy = true;

    try {
      final ok = await ble.reconnectLastDevice();
      if (ok) {
        _onConnected();
        return true;
      }

      await startScan();
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_busy) return;

    _busy = true;
    _state.add(WearableState.connecting);

    try {
      await ble.connectToDevice(device);
      _onConnected();
    } finally {
      _busy = false;
    }
  }

  void _onConnected() async {
    await ble.stopScan();

    _state.add(WearableState.connected);

    _listenToData();
    _startWatchDog();
  }

    // ----------- SCAN ------------

  Future<void> startScan() async {
    await ble.disconnect();

    _state.add(WearableState.scanning);
    await ble.startScan();

    _scanSub?.cancel();
    _scanSub = ble.scanStream.listen(_devices.add);

    Future.delayed(const Duration(seconds: 12), () {
      _state.add(WearableState.notFound);
    });
  }

  // ----------- DATA ------------

  void _listenToData() {
    _dataSub?.cancel();

    _dataSub = ble.stream.listen((p) {
      _lastDataTime = DateTime.now();
      _data.add(p);
      _state.add(WearableState.streaming);
    });
  }

  // ----------- WATCHDOG ------------

  void _startWatchDog() {
    _watchDog?.cancel();

    _watchDog = Timer.periodic(const Duration(seconds: 5), (_) {
      if (DateTime.now().difference(_lastDataTime) > const Duration(seconds: 40)) {
        logStep("WATCHDOG", "Timeout - no data");
        _state.add(WearableState.timeout);
      }
    });
  }

  // ----------- RECONNECT ------------

  Future<bool> reconnect() async {
    if (_busy) return false;

    _state.add(WearableState.connecting);

    await ble.disconnect();
    await Future.delayed(const Duration(seconds: 1));
      
    await connect();
    return true;
  } 

  Future<void> dispose() async {
    await _dataSub?.cancel();
    await _scanSub?.cancel();
    _watchDog?.cancel();
  }
}