import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class ScanList extends StatelessWidget {
  final List<ScanResult> scanResults;
  final Function(BluetoothDevice) onTap;
  final bool Function(ScanResult) isVigil;

  const ScanList({super.key, required this.scanResults, required this.onTap, required this.isVigil});

  String signalLabel(int rssi) {
    if (rssi > -60) return "Strong";
    if (rssi > -75) return "Good";
    return "Weak";
  }

  @override
  Widget build(BuildContext context) {
    if (scanResults.isEmpty) {
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
    scanResults.sort((a, b) => b.rssi.compareTo(a.rssi));
    //final top3 = scanResults.take(3).toList();      // priotize best signal

    return ListView.builder(
      itemCount: scanResults.length,
      itemBuilder: (_, i) {
        final d = scanResults[i];
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

