import 'package:flutter/material.dart';

class NotFoundView extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onPairNew;

  const NotFoundView({super.key, required this.onRetry, required this.onPairNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          const Text("Paired wearable not found", style: TextStyle(fontSize: 20)),
          const SizedBox(height: 12),
          const Text("Make sure your device is powered on and nearby.", textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text("RETRY"),
          ),
          ElevatedButton(
            onPressed: onPairNew,
            child: const Text("PAIR NEW DEVICE"),
          ),
        ],
      ),
    );
  }
}

