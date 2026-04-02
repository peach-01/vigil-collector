import 'dart:async';
import 'package:async/async.dart';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vigil_collector/data/wearable_storage.dart';
import 'package:vigil_collector/logger.dart';
import 'package:vigil_collector/wearables/cmd_builder.dart';
import '../data/sensor_packet.dart';
import 'package:vigil_collector/wearables/protocols.dart';

import 'wearable_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class BleWearableService implements WearableService {
  BluetoothDevice? _device;

  BleProtocol _protocol = UnknownProtocol();

  BluetoothCharacteristic? _writeChar;
  List<BluetoothCharacteristic> _notifyChars = [];

  StreamSubscription? _notifySub;
  StreamSubscription? _connectSub;
  StreamSubscription? _scanResultsSub;

  final _dataController = StreamController<SensorPacket>.broadcast();
  final _scanController = StreamController<List<ScanResult>>.broadcast();

  Timer? _keepAliveTimer;
  bool _isStreaming = false;

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
      await _device!.connect(
        timeout: const Duration(seconds: 5),
        autoConnect: false,
        license: License.free,
      );

      _connectSub?.cancel();
      _connectSub = _device!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          logStep("BLE", "Disconnected");
          _cleanupConnection();
        }
      });

      try {
        await _device!.requestMtu(185);
      } catch (_) {}

      await _setup().timeout(const Duration(seconds: 10));
      return true;
    } catch (e) {
      logStep("BLE", "Connect FAIL: $e");
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
    _cleanupConnection();

    await d?.disconnect();
    await WearableStorage.clear();

    logStep("BLE", "Disconnect SUCCESS");
  }

  void _cleanupConnection() {
    _device = null;
    _notifyChars.clear();
    _writeChar = null;
    _protocol = UnknownProtocol();
    _isStreaming = false;

    _notifySub?.cancel();
    _connectSub?.cancel();
    _keepAliveTimer?.cancel();
  }

  // ----------- SCAN ------------

  @override
  Future<void> startScan() async {
    await FlutterBluePlus.adapterState.where((state) => state == BluetoothAdapterState.on).first;
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    _scanResultsSub?.cancel();
    _scanResultsSub = FlutterBluePlus.scanResults.listen((results) async {
      final nearby = results.where((r) => r.rssi > -90).toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
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
    return name.contains("VIGIL") || adv.contains("VIGIL");
  }

  bool _isCommandDevice() {
    final name = _device?.platformName.toUpperCase() ?? "";
    return name.contains("VIGIL");
  }

  // ----------- SETUP ------------

  Future<void> _setup() async {
    await _discoverServices();
    await _enableNotify();

    if (_isCommandDevice()) {
      await _startStreaming();
    }
  }

  Future<void> _discoverServices() async {
    _notifyChars.clear();
    _writeChar = null;

    final services = await _device!.discoverServices();

    for (final s in services) {
      logStep("BLE", "SERVICE: ${s.uuid}");

      for (final c in s.characteristics) {
        final props = c.properties;
        logStep("BLE", "CHAR: ${c.uuid} | notify=${props.notify} indicate=${props.indicate} write=${props.write} writeNR=${props.writeWithoutResponse}");

        final uuid = c.uuid.toString().toLowerCase();

        // protocol setection
        if (uuid.contains("2a37")) {
          _protocol = HeartRateProtocol();
          logStep("BLE", "Protocol: HeartRate");
        }

        // notify
        if (props.notify || props.indicate) {
          _notifyChars.add(c);
        }

        // write
        if (_writeChar == null && (props.writeWithoutResponse || props.write)) {
          _writeChar = c;
        }
      }
    }

    if (_notifyChars.isEmpty) {
      throw Exception("No notify chars found");
    }
  }

  Future<void> _enableNotify() async {
    await _notifySub?.cancel();

    final streams = <Stream<List<int>>>[];
    
    for (final c in _notifyChars) {
      try {
        await c.setNotifyValue(true);
        streams.add(c.value);
        logStep("BLE", "LISTENING: ${c.uuid}");
      } catch (e) {
        logStep("BLE", "NOTIFY FAIL: ${c.uuid} - $e");
      }
    }

    _notifySub = StreamGroup.merge(streams).listen(_onNotify);
  }

  // ----------- STREAMING ------------

  Future<void> _startStreaming() async {
    if (_writeChar == null || _isStreaming) return;

    _isStreaming = true;

    // Step 1: wake command
    await _write(CommandBuilder.packet(0xA5, [0x01]));
    await Future.delayed(const Duration(milliseconds: 200));

    // Step 2: unlock / mode switch
    await _write(CommandBuilder.packet(0xA2, [0x01]));
    await Future.delayed(const Duration(milliseconds: 300));

    // Step 3: enable sensor system
    await _write(CommandBuilder.packet(0xA0, [0xFF]));

    // Step 4: maintain stream
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _write(CommandBuilder.packet(0xA0, [0x03]));
    });
  }

  Future<void> _write(Uint8List packet) async {
    if (_writeChar == null) {
      logStep("BLE", "NO WRITE CHARACTERISTIC AVAILABLE");
      return;
    }

    try {
      await _writeChar!.write(packet, withoutResponse: true);
    } catch (_) {
      try {
        await _writeChar!.write(packet, withoutResponse: false);
      } catch (e) {
        logStep("BLE", "WRITE FAIL: $e");
      }
    }
  }

  // ----------- NOTIFY ------------

  void _onNotify(List<int> data) {
    if (!_dataController.hasListener) return;

    // protocol fallback
    if (_protocol is UnknownProtocol && data.isNotEmpty) {
      if (data.first == 0x78) {
        _protocol = VigilProtocol();
      }
    }

    try {
      _protocol.onData(data, _dataController);
    } catch (e) {
      logStep("BLE", "PARSE ERROR: $e");
    }
  }
}