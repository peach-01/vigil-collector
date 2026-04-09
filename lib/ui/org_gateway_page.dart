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
  final List<ScanResult> scanResults = [];

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
        scanResults.clear();
        scanResults.addAll(results);
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
              itemCount: scanResults.length,
              itemBuilder: (_, i) {
                final d = scanResults[i];
                final wid = d.device.id.id;
                final deviceName = d.device.name.isNotEmpty ? d.device.name : "Unknown Device";
                final deviceInfo = gateway.devices[wid];
                final userName = deviceInfo?.userName ?? "Unassigned";
                final connectStatus = deviceInfo?.isConnected ?? false ? "Connect" : "Not Connected";

                return ListTile(
                  title: Text(deviceName),
                  subtitle: Text("User: $userName\nStatus: $connectStatus\nID: ${d.device.remoteId.str}"),
                  onTap: () => _connect(d.device),
                );
              },
            ),
          ),
          const Divider(),

          Text("Connected Devices:"),
          ...gateway.connectedIds.map((id) {
            final deviceInfo = gateway.devices[id];
            return Text("${deviceInfo?.device.name ?? 'Unknown Device'} - ${deviceInfo?.userName ?? "Unassigned"}");
          }),
        ],
      ),
    );
  }
}