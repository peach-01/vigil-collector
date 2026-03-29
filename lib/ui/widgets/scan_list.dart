import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class ScanList extends StatelessWidget {
  final List<ScanResult> devices;
  final Function(BluetoothDevice) onTap;
  final bool Function(ScanResult) isVigil;

  const ScanList({super.key, required this.devices, required this.onTap, required this.isVigil});

  String signalLabel(int rssi) {
    if (rssi > -60) return "Strong";
    if (rssi > -75) return "Good";
    return "Weak";
  }

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Scanning for nearby devices..."),
          ],
        ),
      );
    }
    devices.sort((a, b) => b.rssi.compareTo(a.rssi));

    return ListView.builder(
      itemCount: devices.length,
      itemBuilder: (_, i) {
        final d = devices[i];
        final vigil = isVigil(d);

        String displayName = d.device.name.isNotEmpty ? d.device.name : "Unknown Device";
        if (vigil) displayName = "VIGIL • $displayName";

        return ListTile(
          title: Text(displayName),
          subtitle: Text("Signal: ${signalLabel(d.rssi)} (${d.rssi} dBm)"),
          trailing: const Icon(Icons.bluetooth),
          leading: i == 0 ? Icon(Icons.star, color: Colors.amber) : null,
          onTap: () => onTap(d.device),
        );
      },
    );
  }
}

