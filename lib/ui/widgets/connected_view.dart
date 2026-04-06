import 'package:flutter/material.dart';
import 'package:vigil_collector/data/sensor_packet.dart';
import 'package:vigil_collector/wearables/wearable_manager.dart';

class ConnectedView extends StatelessWidget {
  final String deviceId;
  final DateTime? lastUpload;
  final SensorPacket? lastPacket;
  final WearableState status;

  final VoidCallback onReconnect;
  final VoidCallback onUnpair;

  const ConnectedView({super.key, required this.deviceId, required this.lastUpload, required this.lastPacket, required this.status, required this.onReconnect, required this.onUnpair});

  @override
  Widget build(BuildContext context) {
    final hr = lastPacket?.heartRate.toStringAsFixed(0) ?? "--";
    final temp = lastPacket?.temp.toStringAsFixed(1) ?? "--";
    final motion = lastPacket?.motion.toStringAsFixed(1) ?? "--";

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("WEARABLE STATUS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 25, letterSpacing: 6)),

          const SizedBox(height: 20),
          _statusIndicator(),

          const SizedBox(height: 30),
          
          Text("DEVICE ID", style: TextStyle(fontSize: 18, letterSpacing: 2, color: Colors.grey[400])),
          SizedBox(height: 6),
          Text(deviceId.isNotEmpty ? deviceId : "Unknown", style: TextStyle(fontSize: 14)),

          const SizedBox(height: 16),
          if (lastUpload != null)
            Text("Last Sync:   ${lastUpload!.toLocal()}", style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          
          const SizedBox(height: 30),
          //Image.asset('assets/VIGIL_logo_white.png', width: 250, height: 250),
          //const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _metric("HR", hr),
              _metric("TEMP", "$temp°C"),
              _metric("MOTION", motion),
            ],
          ),
          
          const SizedBox(height: 40),

          ElevatedButton(
            onPressed: onReconnect,
            child: const Text("RECONNECT", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
          ),

          ElevatedButton(
            onPressed: onUnpair, 
            child: const Text("UNPAIR DEVICE"),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _statusIndicator() {
    Color color;
    String text;
    IconData icon;

    switch (status) {
      case WearableState.connecting:
        color = Colors.orange;
        text = "Connecting";
        icon = Icons.hourglass_empty;
        break;
      case WearableState.streaming:
        color = Colors.blue;
        text = "Uploading";
        icon = Icons.cloud_upload;
        break;
      case WearableState.connected:
        color = Colors.green;
        text = "Connected";
        icon = Icons.check_circle;
        break;
      case WearableState.error:
        color = Colors.red;
        text = "Error";
        icon = Icons.error;
        break;
      default:
        color = Colors.grey;
        text = "Idle";
        icon = Icons.pause_circle;
  }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 20, color: color)),
      ],
    );
  }
}