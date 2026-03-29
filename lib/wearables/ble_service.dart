import 'dart:async';
import 'package:async/async.dart';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vigil_collector/data/wearable_storage.dart';
import 'package:vigil_collector/logger.dart';
import 'package:vigil_collector/wearables/cmd_builder.dart';
import '../data/sensor_packet.dart';
import 'wearable_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

const String UART_SERVICE =   "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E";
const String UART_RX =        "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
const String UART_TX =        "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

const String CUSTOM_SERVICE =   "DE5BF728-D711-4E47-AF26-65E3012A5DC7";
const String CUSTOM_RX =        "DE5BF72A-D711-4E47-AF26-65E3012A5DC7";
const String CUSTOM_TX =        "DE5BF729-D711-4E47-AF26-65E3012A5DC7";


class BleWearableService implements WearableService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;

  BluetoothCharacteristic? _fee7Write;
  BluetoothCharacteristic? _fee7Notify;

  StreamSubscription? _notifySub;

  final _dataController = StreamController<SensorPacket>.broadcast();
  final _scanController = StreamController<List<ScanResult>>.broadcast();
  
  final List<int> _buffer = [];

  StreamSubscription? _scanResultsSub;

  Timer? _keepAliveTimer;

  @override
  Stream<SensorPacket> get stream => _dataController.stream;

  @override
  Stream<List<ScanResult>> get scanStream => _scanController.stream;
  
  @override
  String get deviceId => _device?.remoteId.str ?? "unknown_device";

  // ----------- CONNECT ------------

  @override
  Future<bool> connect() async {
    if (kIsWeb) throw UnsupportedError("BLE wearables are not supported on Web. Please use the mobile Collector app.");
    if (_device == null) return false;

    try {
      logStep("BLE", "Attempting to pair to devide: $_device");
      await _device!.connect(
        timeout: const Duration(seconds: 5),
        autoConnect: false,
        license: License.free,
      );

      await _setup();
      logStep("BLE", "Connected SUCCESS");
      return true;
    } catch (e) {
      logStep("BLE", "Connect failed: $e");
      return false;
    }
  }

  @override
  Future<void> connectToDevice(BluetoothDevice device) async {
    _device = device;
    await connect();
  }

  @override
  Future<void> disconnect() async {
    final d = _device;

    _device = null;
    _rx = null;
    _tx = null;
    _buffer.clear();

    await _stopStreaming();

    await _notifySub?.cancel();
    await _scanResultsSub?.cancel();

    await d?.disconnect();
    await WearableStorage.clear();

    logStep("BLE", "Disconnect SUCCESS");
  }

  // ----------- SCAN ------------

  @override
  Future<void> startScan() async {
    await FlutterBluePlus.adapterState.where((state) => state == BluetoothAdapterState.on).first;
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    _scanResultsSub?.cancel();
    _scanResultsSub = FlutterBluePlus.scanResults.listen((results) async {
      final nearby = results.where((r) => r.rssi > -75).toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
      final vigilDevices = results.where((r) => _isVigilWearable(r)).toList()..sort((a, b) => b.rssi.compareTo(a.rssi));      
      
      _scanController.add(vigilDevices.isNotEmpty ? vigilDevices : nearby);
    });
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanResultsSub?.cancel();
  }
    
  bool _isVigilWearable(ScanResult r) {
    final name = r.device.name.toUpperCase();
    final adv = r.advertisementData.advName.toUpperCase();
    return name.contains("VIGIL") || adv.contains("VIGIL") || name.contains("DS05") || adv.contains("DS05");
  }

  // ----------- SETUP ------------

  Future<void> _setup() async {
    await _discoverServices();

    // HARD GATE
    if (_tx == null || _fee7Notify == null) throw Exception("Critical characteristic missing");
    logStep("BLE", "SERVICES READY -> enabling notifications");

    // Step 1: enable notifications
    await _fee7Notify!.setNotifyValue(true);
    await _tx!.setNotifyValue(true);
    await Future.delayed(const Duration(milliseconds: 300));

    // Step 2: listen after enabling notify
    await _notifySub?.cancel();
    _notifySub = StreamGroup.merge([
      _tx!.value,
      _fee7Notify!.value,
    ]).listen(_onNotify);
    logStep("BLE", "INIT SEQUENCE START");

    await _deviceInit();
    logStep("BLE", "INIT COMPLETE -> START STREAM");

    await _startStreaming();
  }

  Future<void> _deviceInit() async {
    // Step 1: Time sync
    await _write(_buildTimeSync());
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 2: User profile
    await _write(_buildUserProfile());
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 3: binding trigger (optional)
    await _write(CommandBuilder.packet(0x03, [0x01]));
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<void> _discoverServices() async {
    final services = await _device!.discoverServices();

    for (final s in services) {
      if (s.uuid.toString().toUpperCase() == "FEE7") {
        for (final c in s.characteristics) {
          if (c.uuid.toString().toUpperCase() == "FEA2") {
            _fee7Write = c;
          }
          if (c.uuid.toString().toUpperCase() == "FEA1") {
            _fee7Notify = c;
          }
        }
      }
      if (s.uuid.toString().toUpperCase() == CUSTOM_SERVICE) {
      for (final c in s.characteristics) {
        if (c.uuid.toString().toUpperCase() == CUSTOM_RX) {
          _rx = c; // write
        }
        if (c.uuid.toString().toUpperCase() == CUSTOM_TX) {
          _tx = c; // notify
        }
      }
    }
    }
  }

  Future<void> _startStreaming() async {
    if (_fee7Write == null && _rx == null) {
      logStep("BLE", "No write characteristic available");
      return;
    }

    // Step 1: start streaming
    await _write(CommandBuilder.startRealTimeHR());
    await Future.delayed(const Duration(seconds: 1));

    // Step 2: maintain stream
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 3), 
      (_) => _write(CommandBuilder.holdRealTimeHR()),
    );
  }

  Future<void> _stopStreaming() async {
    await _write(CommandBuilder.stopRealTimeHR());
    _keepAliveTimer?.cancel();
  }

  Uint8List _buildTimeSync() {
    final now = DateTime.now();

    return CommandBuilder.packet(0x01, [
      now.year - 2000,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    ]);
  }

  Uint8List _buildUserProfile() {
    return CommandBuilder.packet(0x02, [
      0x01,   // metric
      25,     // age
      175,    // height
      70,     // weight
      0x00,   // gender
    ]);
  }

  Future<void> _write(Uint8List packet) async {
    if (_fee7Write != null) {
      await _fee7Write!.write(packet, withoutResponse: false);
    } else if (_rx != null) {
      await _rx!.write(packet, withoutResponse: false);
    }
  }

  // ----------- NOTIFY ------------

  void _onNotify(List<int> data) {
    if (data.isEmpty) return;

    _buffer.addAll(data);
    logStep("BLE", "BUFFER LEN: ${_buffer.length}");
    if (_buffer[0] != 0x78) {
      logStep("BLE", "DESYNC DROPPING BYTE ${_buffer[0]}");
    }
    while (_buffer.length >= 16) {
      if (_buffer[0] != 0x78) {
        _buffer.removeAt(0);          // find frame start
        continue;
      }

      final frame = _buffer.sublist(0, 16);
      _buffer.removeRange(0, 16);
      _parseFrame(frame);
    }
    logStep("BLE", "RAW FRAME: $data");
  }

  void _parseFrame(List<int> frame) {
    final type = frame[3];

    double hr = 0, motion = 0, temp = 0, hrv = 0, sleepQ = 0, sleepT = 0;

    switch (type) {
      case 0x07: // Heart Rate
        hr = frame[5].toDouble();
        logStep("BLE", "HR (live): $hr");
        break;

      case 0x0B:  // Secondary HR? (resting/sleep)
        hr = frame[5].toDouble();
        logStep("BLE", "HR (secondary): $hr");
        break;

      case 0x0D: // Motion
        motion = frame[8].toDouble();   // primary activity
        final motion2 = frame[11];      // secondary signal

        final cumulative = (frame[13] << 8 | frame[14]);
        logStep("BLE", "MOTION: $motion | M2: $motion2 | CUM: $cumulative");
        break;

      case 0x03: // Temp
        temp = frame[3] / 10.0;
        break;

      case 0x15:  // HRV
        hrv = frame[5].toDouble();
        break;

      case 0x16:
        logStep("BLE", "STRESS: ${frame[5]}");
        break;

      case 0x04: // Sleep
        sleepQ = frame[3].toDouble();
        sleepT = frame[4].toDouble();
        break;

      default:
        logStep("BLE", "UNKOWN TYPE: $type DATA: $frame");
    }

    logStep("BLE", "TYPE=$type VALUE=${frame[5]} FULL=$frame");

    _dataController.add(
      SensorPacket(
        heartRate: hr,
        hrv: hrv,
        temp: temp,
        motion: motion,
        sleepQuality: sleepQ,
        sleepTime: sleepT,
      ),
    );
  }
}

/* 
-------------------- PACKET STRUCTURE ------------------
Byte Index      Val           Meaning
--------------------------------------------------------
0               0x78          Start of frame (header)
1               0x07          Packet length / protocol version
2               0x01          Device ID / stream ID
3               varies        SENSOR TYPE
4               increments    counter
5               varies        HR (live)
6-7
8               varies        Activity Level / Motion
9-10
11              varies        Motion Magnitude? (filtered accel?)
12
13
14
15              increments    checksum
--------------------------------------------------------
*/