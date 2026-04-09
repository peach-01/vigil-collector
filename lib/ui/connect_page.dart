import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:vigil_collector/data/data_pipeline.dart';
import 'package:vigil_collector/logger.dart';
import 'package:vigil_collector/ui/widgets/connected_view.dart';
import 'package:vigil_collector/ui/widgets/scan_list.dart';
import 'package:vigil_collector/wearables/wearable_manager.dart';
import '../wearables/ble_service.dart';
import '../wearables/mock_wearable_service.dart';
import '../data/uploader.dart';
import '../data/sensor_packet.dart';

class ConnectWearablePage extends StatefulWidget {
    final String uid;
    const ConnectWearablePage({required this.uid, super.key});

    @override
    State<ConnectWearablePage> createState() => _ConnectWearablePageState();
}

class _ConnectWearablePageState extends State<ConnectWearablePage> {
    late final WearableManager manager;

    StreamSubscription? stateSub;
    StreamSubscription? dataSub;
    StreamSubscription? deviceSub;
    
    DateTime? lastUpload;
    SensorPacket? lastPacket;

    DataPipeline? pipeline;

    WearableState mode = WearableState.scanning;
    List<ScanResult> devices = [];

    bool _registered = false;
    late final FirestoreUploader uploader;


    @override
    void initState() {
      super.initState();

      final ble = kIsWeb ? MockWearableService() : BleWearableService();
      manager = WearableManager(ble);

      _init();
    }

    Future<void> _init() async {
      uploader = FirestoreUploader();

      stateSub = manager.state.listen((state) async {
        if (!mounted) return;
        if (mode != state) setState(() => mode = state);

        // register after connect
        if ((state == WearableState.connected) && !_registered) {
          _registered = true;
          
          final wid = manager.ble.deviceId;
          if (wid == "unknown_device") return;
          
          try {
            await uploader.registerWearable(
              uid: widget.uid, 
              wearableId: wid, 
              type: "heart_rate_monitor",
            );

            pipeline?.dispose();
            pipeline = DataPipeline(uploader: uploader, ownerId: widget.uid, wid: wid);

            if (kDebugMode) logStep("CONNECT", "Wearable registered: $wid");
          } catch (e) {
            if (kDebugMode) logStep("CONNECT", "Registration FAILED: $e");
            _registered = false;
          }
        }

        if (state == WearableState.scanning) {
          _registered = false;
        }
      });

      deviceSub = manager.devices.listen((list) async {
        if (!mounted) return;
        setState(() => devices = list);

        // AUTO-CONNECT LOGIC
        if (mode == WearableState.scanning && list.isNotEmpty) {
          final best = list.first;

          // connection to VIGIL devices only
          if (_isVigilWearable(best)) {
            await manager.connectToDevice(best.device);
          }
        }
      });

      dataSub = manager.data.listen((packet) async {
        lastPacket = packet;
        if (_isValidPacket(packet)) {
          pipeline?.add(packet);
        }

        if (mounted) {
          setState(() => lastUpload = DateTime.now());
        }
      });

      smartStartup();
    }

    bool _isValidPacket(SensorPacket p) {
      return p.heartRate > 0 || p.temp > 0 || p.motion > 0 || p.hrv > 0;
    }

    bool _isVigilWearable(ScanResult r) {
      final name = r.device.name.toUpperCase();
      final adv = r.advertisementData.advName.toUpperCase();
      return (
        name.contains("VIGIL") || adv.contains("VIGIL") ||
        
        name.startsWith("H303") || adv.startsWith("H303") ||
        name.startsWith("HW706") || adv.startsWith("HW706")
      );
    }

    Future<void> smartStartup() async {
      // Stage 1: silent reconnect attempt (fast)
      final s = await manager.reconnect();
      if (s) return;

      // Stage 2: background scan (no UI switch yet)
      await manager.startScan(silent: true);

      // Stage 3: after delay, show device list
      Future.delayed(const Duration(seconds: 25), () {
        manager.enableScanUI();
      });
    }

    Future<void> _logout() async {
      dispose();
      await manager.ble.disconnect();
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }

    @override
    void dispose() {
      deviceSub?.cancel();
      stateSub?.cancel();
      dataSub?.cancel();
      pipeline?.dispose();

      manager.dispose();
      super.dispose();
    }

    @override
    Widget build(BuildContext context) {
        Widget body;

        switch (mode) {
          case WearableState.scanning:
            body = manager.shouldShowScanUI
              ? ScanList(
                  devices: devices, 
                  isVigil: _isVigilWearable, 
                  onTap: (device) async {
                    await manager.connectToDevice(device);
                  },
              )
              : _scanningView(); 
            break;

          case WearableState.connecting:
            body = const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Connecting..."),
                ],
              )
            );
            break;

          case WearableState.connected:
            body = ConnectedView(
              deviceId: manager.ble.deviceId, 
              lastUpload: lastUpload, 
              lastPacket: lastPacket, 
              status: mode, 
              onUnpair: manager.ble.disconnect,
            );
            break;
        }

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Image.asset('assets/VIGIL_logo_white.png', width: 60, height: 60),
                SizedBox(width: 12),
                Text("VIGIL CONNECT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 3)),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.logout),
                onPressed: _logout,
              ),
            ],
          ),
          body: body,
        );
    }
}

Widget _scanningView() {
  return const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text("Connecting to your device..."),
      ],
    ),
  );
}