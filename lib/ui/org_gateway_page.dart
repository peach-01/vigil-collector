import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vigil_collector/data/uploader.dart';
import 'package:vigil_collector/ui/widgets/scan_list.dart';
import 'package:vigil_collector/wearables/ble_service.dart';
import 'package:vigil_collector/wearables/gateway_manager.dart';
import 'package:vigil_collector/wearables/wearable_manager.dart';

class OrgGatewayPage extends StatefulWidget {
  final String orgId;

  const OrgGatewayPage({required this.orgId, super.key});

  @override
  State<OrgGatewayPage> createState() => _OrgGatewayPageState();
}

class _OrgGatewayPageState extends State<OrgGatewayPage> {
  late GatewayManager gateway;
  late WearableManager scanManager;

  StreamSubscription? scanSub;
  StreamSubscription? updateSub;
  
  WearableState mode = WearableState.scanning;
  

  List<ScanResult> scanResults = [];

  @override
  void initState() {
    super.initState();

    final uploader = FirestoreUploader();
    gateway = GatewayManager(uploader: uploader, orgId: widget.orgId);
    
    final ble = BleWearableService();
    scanManager = WearableManager(ble);

    updateSub = gateway.updates.listen((_) {
      if (mounted) setState(() {});
    });

    _init();
  }

  Future<void> _init() async {
    scanSub = scanManager.devices.listen((list) async {
      if (!mounted) return;

      setState(() => scanResults = list);

      if (mode == WearableState.scanning && list.isNotEmpty) {
        final best = list.first;

        if (_isVigilWearable(best)) {
          setState(() => mode = WearableState.connecting);

          await gateway.addDevice(best.device);

          setState(() => mode = WearableState.connected);
        }
      }
    });

    await scanManager.startScan(silent: false);
  }

  bool _isVigilWearable(ScanResult r) {
    final name = r.device.name.toUpperCase();
    final adv = r.advertisementData.advName.toUpperCase();

    return (
      name.contains("VIGIL") || adv.contains("VIGIL") ||
      name.contains("H303") || adv.contains("H303") ||
      name.contains("HW706") || adv.contains("HW706")
    );
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() => mode = WearableState.connecting);
    await gateway.addDevice(device);
    setState(() => mode = WearableState.connected);
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    switch (mode) {
      case WearableState.scanning:
        body = ScanList(
          scanResults: scanResults,
          onTap: _connect,
          isVigil: _isVigilWearable,
        );
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
          ),
        );
        break;

      case WearableState.connected:
        body = _connectedView();
        break;
    }

    return Scaffold(
      appBar: AppBar(title: const Text("ORG GATEWAY")),
      body: body,
    );
  }

  Widget _connectedView() {
    final devices = gateway.allDevices;

    if (devices.isEmpty) {
      return const Center(child: Text("No devices connected"));
    }

    return ListView(
      children: devices.map((d) {
        final hr = d.lastPacket?.heartRate.toStringAsFixed(0) ?? "--";

        return ListTile(
          title: Text(d.manager.ble.deviceId),
          subtitle: Text(d.assignedUserName ?? "Unassigned"),
          trailing: Text("HR: $hr"),
        );
      }).toList(),
    );
  }
}