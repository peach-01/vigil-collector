import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:vigil_collector/data/sensor_packet.dart';
import 'package:vigil_collector/logger.dart';
import 'package:vigil_collector/utils/consts.dart';
import 'package:vigil_collector/wearables/wearable_service.dart';


enum WearableState {
  scanning,
  connecting,
  connected,
}

class WearableManager {
  final WearableService ble;

  final _state = StreamController<WearableState>.broadcast();
  final _data = StreamController<SensorPacket>.broadcast();
  final _devices = StreamController<List<ScanResult>>.broadcast();

  StreamSubscription? _dataSub;
  StreamSubscription? _scanSub;

  bool _foundAnyDevice = false;
  bool _busy = false;
  bool _reconnecting = false;
  bool _silentScanning = false;
  bool _showScanUI = false;

  Timer? _scanTimeout;
  Timer? _watchDog;

  String? _lastDeviceId;
  Set<String>? allowedIds;

  DateTime _lastDataTime = DateTime.now();
  DateTime _lastForward = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _connectedAt;

  static const _initGrace = Duration(seconds: 15);

  WearableManager(this.ble);

  Stream<WearableState> get state => _state.stream;
  Stream<SensorPacket> get data => _data.stream;
  Stream<List<ScanResult>> get devices => _devices.stream;

  bool get shouldShowScanUI => _showScanUI;


  // ----------- CONNECT ------------

  Future<bool> connect() async {
    if (_busy) return false;
    
    _busy = true;
    _state.add(WearableState.connecting);

    try {
      final ok = await ble.reconnectLastDevice();
      if (ok) {
        _onConnected();
        _lastDeviceId = ble.deviceId;
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
    _scanTimeout?.cancel();

    await ble.stopScan();

    _connectedAt = DateTime.now();
    _lastDataTime = DateTime.now();

    _state.add(WearableState.connected);

    _listenToData();
    _startWatchDog();
  }

    // ----------- SCAN ------------

  Future<void> startScan({bool silent = false}) async {
    _silentScanning = silent;
    _showScanUI = !silent;

    if (_state != WearableState.connected) {
      await ble.disconnect();
    }
    
    _state.add(WearableState.scanning);
    await ble.startScan();

    _scanSub?.cancel();
    _scanSub = ble.scanStream.listen((devices) async {
      final filtered = allowedIds == null ? devices : devices.where((d) => allowedIds!.contains(normalizeId(d.device.remoteId.str))).toList();
      _devices.add(filtered);

      // AUTO-CONNECT best match
      if (filtered.isNotEmpty) {
        _foundAnyDevice = true;
        final best = filtered.first;
        if (_isReconnectTarget(best)) {
          await connectToDevice(best.device);
        }
      }

      if (filtered.isEmpty) {
        enableScanUI();
      }
    });

    _scanTimeout?.cancel();
    _scanTimeout = Timer(const Duration(seconds: 12), () async {
      if (!_foundAnyDevice) {
        if (kDebugMode) logStep("SCAN", "No devices found, retrying...");
        await startScan();    // auto retry
      }
    });
  }

  Future<void> startScanBurst() async {
    await startScan();
    await Future.delayed(Duration(seconds: 5));
    await ble.stopScan();
  }

  bool _isReconnectTarget(ScanResult r) {
    return r.device.remoteId.str == _lastDeviceId;
  }

  void enableScanUI() {
    _showScanUI = true;
    _state.add(WearableState.scanning);
  }

  // ----------- DATA ------------

  void _listenToData() {
    _dataSub?.cancel();
    _dataSub = ble.stream.listen((p) {
      final now = DateTime.now();

      if (now.difference(_lastForward) < const Duration(seconds: 10)) return;
      _lastForward = now;

      _lastDataTime = now;
      _data.add(p);
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
        if (kDebugMode) logStep("WATCHDOG", "Lost connection");
        await startReconnectLoop();
      }
    });
  }

  // ----------- RECONNECT ------------

  Future<bool> reconnect() async {
    if (_busy) return false;

    _busy = true;
    _reconnecting = true;
    _state.add(WearableState.connecting);

    try {
      await ble.disconnect();
      await Future.delayed(const Duration(seconds: 2));
      return await connect();
    } catch (e) {
      if (kDebugMode) logStep("RECONNECT", "Reconnection FAIL: $e");
      return false;
    } finally {
      _busy = false;
      _reconnecting = false;
    }
  } 

  Future<void> startReconnectLoop() async {
    if (_reconnecting) return;

    _busy = true;
    _reconnecting = true;
    _state.add(WearableState.connecting);

    while (_reconnecting) {
      if (kDebugMode) logStep("RECONNECT", "Attempting...");
      final s = await ble.reconnectLastDevice();

      if (s) {
        _onConnected();

        _reconnecting = false;
        _busy = false;
        return;
      }

      // fallback to scan
      await ble.startScan();
      await Future.delayed(const Duration(seconds: 5));
      await ble.stopScan();

      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> dispose() async {
    await _dataSub?.cancel();
    await _scanSub?.cancel();
    _watchDog?.cancel();
  }
}