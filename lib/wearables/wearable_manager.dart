import 'dart:async';
import 'package:flutter/foundation.dart';
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
  DateTime? _connectedAt;

  static const _initGrace = Duration(seconds: 15);

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

    _connectedAt = DateTime.now();
    _lastDataTime = DateTime.now();

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

    DateTime _lastForward = DateTime.fromMillisecondsSinceEpoch(0);

    _dataSub = ble.stream.listen((p) {
      final now = DateTime.now();

      if (now.difference(_lastForward) < const Duration(seconds: 10)) return;
      _lastForward = now;

      _lastDataTime = now;
      _data.add(p);
      _state.add(WearableState.streaming);
    });
  }

  // ----------- WATCHDOG ------------

  void _startWatchDog() {
    _watchDog?.cancel();

    _watchDog = Timer.periodic(const Duration(seconds: 5), (_) async {
      final now = DateTime.now();

      // skip watchdog during init connect window
      if (_connectedAt != null && now.difference(_connectedAt!) < _initGrace) return;

      final diff = now.difference(_lastDataTime);
      if (diff > const Duration(seconds: 40)) {
        if (kDebugMode) logStep("WATCHDOG", "Timeout - reconnecting");
        _state.add(WearableState.timeout);
        await reconnect();
      }
    });
  }

  // ----------- RECONNECT ------------

  Future<bool> reconnect() async {
    if (_busy) return false;
    _busy = true;

    try {
      await ble.disconnect();
      await Future.delayed(const Duration(seconds: 2));
        
      return await connect();
    } catch (e) {
      _state.add(WearableState.error);
      return false;
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