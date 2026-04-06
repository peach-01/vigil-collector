import 'dart:async';
import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vigil_collector/data/wearable_storage.dart';
import 'package:vigil_collector/logger.dart';
import 'package:vigil_collector/wearables/cmd_builder.dart';
import '../data/sensor_packet.dart';
import 'package:vigil_collector/wearables/protocols.dart';
import 'wearable_service.dart';

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

  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  bool _isStreaming = false;
  bool _isConnecting = false;

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
    if (_device == null || _isConnecting) return false;
    _isConnecting = true;

    try {
      await _ensureAdapterOn();

      await _device!.connect(
        timeout: const Duration(seconds: 8),
        autoConnect: false,
        license: License.free,
      );

      _listenConnectState();
      await _setup();

      await WearableStorage.saveLastDevice(_device!.remoteId.str);

      return true;
    } catch (e) {
      if (kDebugMode) logStep("BLE", "Connect FAIL: $e");
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  void _listenConnectState() {
    _connectSub?.cancel();
    _connectSub = _device!.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.disconnected) {
        if (kDebugMode) logStep("BLE", "Disconnected");

        final lastId = _device?.remoteId.str;

        _cleanupConnection();

        // auto-reconnect
        if (lastId != null) {
          await Future.delayed(const Duration(seconds: 4));

          try {
            _device = BluetoothDevice.fromId(lastId);
            if (kDebugMode) logStep("BLE", "Auto-reconnecting");
            await connect();
          } catch (e) {
            if (kDebugMode) logStep("BLE", "Auto-reconnect FAIL: $e");
          }
        }
      }
    });
  }

  Future<void> _ensureAdapterOn() async {
    await FlutterBluePlus.adapterState.where((s) => s == BluetoothAdapterState.on).first;
  }

  @override
  Future<void> connectToDevice(BluetoothDevice device) async {
    _device = device;
    await connect();
  }

  @override
  Future<bool> reconnectLastDevice() async {
    final wid = await WearableStorage.getLastDevice();
    if (wid == null) return false;

    try {
      _device = BluetoothDevice.fromId(wid);
      if (kDebugMode) logStep("BLE", "Reconnecting to $wid");
      return await connect();
    } catch (e) {
      if (kDebugMode) logStep("BLE", "Reconnect FAIL: $e");
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    final d = _device;
    _cleanupConnection();

    await d?.disconnect();
    await WearableStorage.clear();

    if (kDebugMode) logStep("BLE", "Disconnect SUCCESS");
  }

  void _cleanupConnection() {
    _protocol = UnknownProtocol();

    _notifyChars.clear();
    _writeChar = null;

    _notifySub?.cancel();
    _connectSub?.cancel();
    _keepAliveTimer?.cancel();

    _isStreaming = false;
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
    return (
      name.contains("VIGIL") || adv.contains("VIGIL") ||
      name.contains("H303") || adv.contains("H303") ||
      name.contains("H6") || adv.contains("H6") ||
      name.contains("HW706") || adv.contains("HW706")
    );
  }

  // ----------- SETUP ------------

  Future<void> _setup() async {
    try {
      await _discoverServices();
      await _enableNotify();

      if (_writeChar != null && !_isStreaming) {
        await _startStreaming();
      }
    } catch (e) {
      if (kDebugMode) logStep("BLE", "Setup FAIL: $e");
    }
  }

  Future<void> _discoverServices() async {
    _notifyChars.clear();
    _writeChar = null;

    final services = await _device!.discoverServices();

    for (final s in services) {
      for (final c in s.characteristics) {
        final props = c.properties;
        final uuid = c.uuid.toString().toLowerCase();

        // protocol selection
        if (uuid.contains("2a37")) {
          _protocol = HeartRateProtocol();
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
      throw Exception("No notify characteristics found");
    }
  }

  Future<void> _enableNotify() async {
    await _notifySub?.cancel();

    final streams = <Stream<List<int>>>[];
    
    for (final c in _notifyChars) {
      try {
        await c.setNotifyValue(true);
        streams.add(c.value);
        if (kDebugMode) logStep("BLE", "LISTENING: ${c.uuid}");
      } catch (e) {
        if (kDebugMode) logStep("BLE", "NOTIFY FAIL: ${c.uuid} - $e");
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
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 4: maintain stream
    if (DateTime.now().difference(_lastEmit) > Duration(seconds: 5)) {
      await _write(CommandBuilder.packet(0xA0, [0x03]));
    }
  }

  Future<void> _write(Uint8List packet) async {
    if (_writeChar == null) return;

    final now = DateTime.now();
    if (now.difference(_lastWrite).inMilliseconds < 400) return;
    _lastWrite = now;

    try {
      await _writeChar!.write(packet, withoutResponse: true);
    } catch (_) {
      try {
        await _writeChar!.write(packet, withoutResponse: false);
      } catch (e) {
        if (kDebugMode) logStep("BLE", "WRITE FAIL: $e");
      }
    }
  }

  // ----------- NOTIFY ------------

  void _onNotify(List<int> data) {
    if (!_dataController.hasListener) return;

    // protocol fallback
    if (_protocol is UnknownProtocol && data.isNotEmpty && data.first == 0x78) {
      _protocol = VigilProtocol();
    }

    try {
      _protocol.onData(data, _dataController);
    } catch (e) {
      if (kDebugMode) logStep("BLE", "PARSE ERROR: $e");
    }
  }
}