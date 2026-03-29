
import 'package:flutter/material.dart';

class TimeoutView extends StatelessWidget {
  final VoidCallback onRescan;

  const TimeoutView({super.key, required this.onRescan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer_off, size: 64, color: Colors.orange),
          const SizedBox(height: 16),
          const Text("Connection timed out", style: TextStyle(fontSize: 20)),
          const SizedBox(height: 12),
          const Text("We stopped receiving data from your wearable."),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onRescan,
            child: const Text("RESCAN"),
          ),
        ],
      ),
    );
  }
}