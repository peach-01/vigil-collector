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

  List<ScanResult> scanResults = [];

  @override
  void initState() {
    super.initState();

    final uploader = FirestoreUploader();
    gateway = GatewayManager(uploader: uploader, orgId: widget.orgId);
    
    final ble = BleWearableService();
    scanManager = WearableManager(ble);

    _initScan();
  }

  Future<void> _initScan() async {
    scanSub = scanManager.devices.listen((list) {
      setState(() => scanResults = list);
    });

    await scanManager.startScan(silent: false);
  }

  Future<void> _connect(BluetoothDevice device) async {
    await gateway.addDevice(device);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("ORG GATEWAY"),
      ),
      body: Column(
        children: [
          Expanded(
            child: ScanList(
              scanResults: scanResults, 
              onTap: _connect, 
              isVigil: (r) => true,
            ),
          ),
          const Divider(),

          Expanded(
            child: ListView(
              children: gateway.allDevices.map((d) {
                final hr = d.lastPacket?.heartRate.toStringAsFixed(0) ?? "--";

                return ListTile(
                  title: Text(d.manager.ble.deviceId),
                  subtitle: Text(d.assignedUserName ?? "Unassigned"),
                  trailing: Text("HR: $hr"),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}