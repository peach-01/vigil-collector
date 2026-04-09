import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vigil_collector/data/uploader.dart';
import 'package:vigil_collector/wearables/gateway_manager.dart';

class OrgGatewayPage extends StatefulWidget {
  final String orgId;

  const OrgGatewayPage({required this.orgId, super.key});

  @override
  State<OrgGatewayPage> createState() => _OrgGatewayPageState();
}

class _OrgGatewayPageState extends State<OrgGatewayPage> {
  late GatewayManager gateway;
  final List<ScanResult> devices = [];

  @override
  void initState() {
    super.initState();

    final uploader = FirestoreUploader();

    gateway = GatewayManager(uploader: uploader, orgId: widget.orgId);
    _startScan();
  }

  Future<void> _startScan() async {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        devices.clear();
        devices.addAll(results);
      });
    });
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
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (_, i) {
                final d = devices[i];

                return ListTile(
                  title: Text(d.device.name.isNotEmpty ? d.device.name : "Unknown Device"),
                  subtitle: Text(d.device.remoteId.str),
                  onTap: () => _connect(d.device),
                );
              },
            ),
          ),
          const Divider(),

          Text("Connected Devices:"),
          ...gateway.connectedIds.map((id) => Text(id)).toList(),
        ],
      ),
    );
  }
}