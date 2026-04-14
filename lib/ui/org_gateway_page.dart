import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vigil_collector/data/gateway_device.dart';
import 'package:vigil_collector/data/uploader.dart';
import 'package:vigil_collector/logger.dart';
import 'package:vigil_collector/ui/widgets/scan_list.dart';
import 'package:vigil_collector/utils/consts.dart';
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

  final int maxConnections = 7;
  final Set<String> connectingDevices = {};   // prevent duplicates

  List<ScanResult> scanResults = [];

  bool showScanPanel = false;   // scan list toggle
  bool _isLoggingOut = false;

  StreamSubscription? scanSub;
  StreamSubscription? updateSub;

  String formatWid(String wid) {
    if (wid.length <= 8) return wid;
    return "${wid.substring(0,4)}...${wid.substring(wid.length-4)}";
  }

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
    await gateway.init();

    scanSub = scanManager.devices.listen(_handleScanResults);

    // Step 1: silent scan
    await scanManager.startScan(silent: false);

    // Step 2: UI fallback
    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && gateway.devices.isEmpty) {
        setState(() => showScanPanel = true);
      }
    });
  }

  void _handleScanResults(List<ScanResult> list) {
    if (!mounted) return;

    setState(() => scanResults = list);

    if (gateway.allowedWearables.isEmpty) return;
    if (gateway.devices.length >= maxConnections) return;
    
    final candidates = list.where(_isVigilWearable).where((r) => gateway.allowedWearables.contains(normalizeId(r.device.remoteId.str))).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    for (final r in candidates) {
      final wid = r.device.remoteId.str;

      if (gateway.devices.containsKey(wid)) continue;
      if (connectingDevices.contains(wid)) continue;

      connectingDevices.add(wid);
      _connectDevice(r.device);
      
    }
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


  // ------------------ CONNECT ------------------

  Future<void> _connect(BluetoothDevice device) async {
    await gateway.addDevice(device, manual: true);
  }

  void _connectDevice(BluetoothDevice device) async {
    try {
      await gateway.addDevice(device);
    } catch (e) {
      logStep("GATEWAY", "Connection FAIL: $e");
    } finally {
      connectingDevices.remove(device.remoteId.str);
      if (mounted) setState(() {});
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;

    try {
      await scanSub?.cancel();
      await updateSub?.cancel();

      await scanManager.ble.disconnect();
      await gateway.dispose();
      await scanManager.ble.disconnect();

      await FirebaseAuth.instance.signOut();
    } catch (e) {
      logStep("AUTH", "Logout error: $e");
    }
    
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Widget _deviceDetails(GatewayDevice d) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow("Status", d.state.toString().split('.').last),
          _infoRow("Last Upload", d.lastUploadAgo),
          _infoRow("Connect Time", d.connectionDuration),
          _infoRow("Last HR", d.lastPacket?.heartRate.toStringAsFixed(0) ?? "--"),

          _infoRow("Battery", d.batteryLevel != null ? "${d.batteryLevel}%" : "Unknown"),
          _infoRow("Signal", d.signalQuality),
          _infoRow("Last Seen", d.lastSeen != null ? "${DateTime.now().difference(d.lastSeen!).inSeconds}s ago" : "Unknown"),
          
          if (d.statusNote != null)
            _infoRow("Note", d.statusNote!),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasDevices = gateway.devices.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/VIGIL_logo_white.png', width: 60, height: 60),
            SizedBox(width: 12),
            Text("ORG GATEWAY (${gateway.devices.length}/$maxConnections)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 3)),
          ],
        ),
        actions: [
          IconButton(icon: Icon(Icons.logout), onPressed: _logout),
          IconButton(
            icon: Icon(Icons.bluetooth_searching),
            onPressed: () {
              setState(() => showScanPanel = !showScanPanel);
            },
          ),
        ],
      ),
      body: hasDevices ? _connectedView() : _scanningView(),
    );
  }

  Widget _connectedView() {
    final devices = gateway.devices.entries.toList();

    return Column(
      children: [
        if (showScanPanel)
          SizedBox(
            height: 250,
            child: ScanList(
              scanResults: scanResults, 
              onTap: _connect, 
              isVigil: _isVigilWearable,
            ),
          ),
          Expanded(
            child: devices.isEmpty 
                ? const Center(child: Text("No devices connected"))
                : ListView(
                  children: devices.map((entry) {
                    final wid = entry.key;
                    final d = entry.value;

                    final hr = d.lastPacket?.heartRate.toStringAsFixed(0) ?? "--";

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      elevation: 3,
                      child: ExpansionTile(
                        title: Text(formatWid(wid), style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(d.assignedUserName ?? "Unassigned"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("HR: $hr"),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () {
                                gateway.disconnectDevice(wid);
                              },
                            ),
                          ],
                        ),
                        children: [
                          _deviceDetails(d),
                        ],
                      ),
                    );
                  }).toList(),
                ),
          ),
      ],
    );
  }

  Widget _scanningView() {
    if (showScanPanel) {
      return ScanList(scanResults: scanResults, onTap: _connect, isVigil: _isVigilWearable);
    }

    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text("Searching for organization devices..."),
        ],
      ),
    );
  }
}