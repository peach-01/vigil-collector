import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:vigil_collector/data/data_pipeline.dart';
import 'package:vigil_collector/logger.dart';

import 'package:vigil_collector/ui/widgets/connected_view.dart';
import 'package:vigil_collector/ui/widgets/not_found_view.dart';
import 'package:vigil_collector/ui/widgets/scan_list.dart';
import 'package:vigil_collector/ui/widgets/timeout_view.dart';
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

    WearableState mode = WearableState.idle;
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
        if ((state == WearableState.connected || state == WearableState.streaming) && !_registered) {
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
            pipeline = DataPipeline(uploader: uploader, uid: widget.uid, wid: wid);

            if (kDebugMode) logStep("CONNECT", "Wearable registered: $wid");
          } catch (e) {
            if (kDebugMode) logStep("CONNECT", "Registration FAILED: $e");
            _registered = false;
          }
        }

        if (state == WearableState.idle || state == WearableState.scanning) {
          _registered = false;
        }
      });

      deviceSub = manager.devices.listen((list) {
        if (!mounted) return;
        setState(() => devices = list);
      });

      dataSub = manager.data.listen((packet) async {
        lastPacket = packet;
        pipeline?.add(packet);

        if (mounted) {
          setState(() => lastUpload = DateTime.now());
        }
      });

      final reconnected = await manager.reconnect();

      if (!reconnected) {
        await manager.startScan();  // scan falback
      }
    }

    bool _isVigilWearable(ScanResult r) {
      final name = r.device.name.toUpperCase();
      final adv = r.advertisementData.advName.toUpperCase();
      return name.contains("VIGIL") || adv.contains("VIGIL") || name.contains("DS05") || adv.contains("DS05");
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
          case WearableState.idle:
            body = const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Searching for nearby VIGIL devices..."),
                ],
              )
            );
            break;

          case WearableState.scanning:
            body = ScanList(
              devices: devices, 
              isVigil: _isVigilWearable, 
              onTap: (device) async {
                await manager.connectToDevice(device);
              },
            );
            break;

          case WearableState.connecting:
            body = const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Connecting to device..."),
                ],
              )
            );
            break;

          case WearableState.connected:
          case WearableState.streaming:
            body = ConnectedView(
              deviceId: manager.ble.deviceId, 
              lastUpload: lastUpload, 
              lastPacket: lastPacket, 
              status: mode, 
              onReconnect: manager.reconnect, 
              onUnpair: manager.ble.disconnect,
            );
            break;

          case WearableState.timeout:
            body = TimeoutView(onRescan: manager.startScan);
            break;

          case WearableState.notFound:
            body = NotFoundView(
              onRetry: manager.startScan, 
              onPairNew: manager.connect,
            );
            break;

          case WearableState.error:
            body = Center(child: Text("Error"));
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