import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vigil_collector/logger.dart';
import '../wearables/ble_service.dart';
import '../wearables/mock_wearable_service.dart';
import '../data/uploader.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../data/sensor_packet.dart';

enum CollectorStatus {
    idle,
    connecting,
    connected,
    uploading,
    error,
}

class ConnectWearablePage extends StatefulWidget {
    final String uid;
    const ConnectWearablePage({required this.uid, super.key});

    @override
    State<ConnectWearablePage> createState() => _ConnectWearablePageState();
}

class _ConnectWearablePageState extends State<ConnectWearablePage> {
    final ble = kIsWeb ? MockWearableService() : BleWearableService();

    StreamSubscription? sub;
    CollectorStatus status = CollectorStatus.idle;
    String? errorMessage;
    DateTime? lastUpload;
    SensorPacket? lastPacket;

    @override
    void initState() {
        super.initState();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _start();
        });
    }

    Future<void> _start() async {
        logStep("FLOW", "_start() CALLED");

        try {
            setState(() {
              status = CollectorStatus.connecting;
              errorMessage = null;
            });

            //logStep("FLOW", "Calling ble.connect()");
            await ble.connect();
            //logStep("FLOW", "ble.connect() DONE");

            setState(() => status = CollectorStatus.connected);

            final user = FirebaseAuth.instance.currentUser;
            logStep("FLOW", "User: ${user?.uid}");

            if (user == null) throw Exception("User not logged in");

            logStep("FLOW", "Fetching token...");
            final token = await user.getIdToken();
            logStep("FLOW", "Token received");

            final uploader = FirestoreUploader();

            // Register device once
            logStep("FLOW", "Registering wearable...");
            await uploader.registerWearable(uid: widget.uid, wearableId: ble.deviceId, type: 'G69');
            logStep("FLOW", "Wearable registered");

            DateTime _lastUpload = DateTime.fromMillisecondsSinceEpoch(0);

            sub = ble.stream.listen((packet) async {
                logStep("STREAM", "Packet received: HR=${packet.heartRate}");

                final now = DateTime.now();
                if (now.difference(_lastUpload).inSeconds < 15) return;  // data upload throttle
                
                _lastUpload = now;
                
                setState(() {
                    status = CollectorStatus.uploading;
                    lastPacket = packet;
                });

                await uploader.ingestTelemetry(uid: widget.uid, wid: ble.deviceId, packet: packet);
                
                setState(() => lastUpload = now);
            });
        } catch (e) {
            logStep("ERROR", e.toString());
            setState(() { 
                status = CollectorStatus.error;
                errorMessage = e.toString();
            });
            await Future.delayed(const Duration(seconds: 3));
            if (mounted) _start();  // auto retry
        }
        
    }

    @override
    void dispose() {
        sub?.cancel();
        ble.disconnect();
        super.dispose();
    }

    Widget _statusIndicator() {
        Color color;
        String text;
        IconData icon;

        switch (status) {
            case CollectorStatus.connecting:
                color = Colors.orange;
                text = "Connecting";
                icon = Icons.hourglass_empty;
                break;
            case CollectorStatus.uploading:
                color = Colors.blue;
                text = "Uploading";
                icon = Icons.cloud_upload;
                break;
            case CollectorStatus.connected:
                color = Colors.green;
                text = "Connected";
                icon = Icons.check_circle;
                break;
            case CollectorStatus.error:
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

    @override
    Widget build(BuildContext context) {
        logStep("UI", "BUILD CALLED - status: $status");

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                //Image.asset('assets/VIGIL_logo_white.png', width: 60, height: 60),
                //SizedBox(width: 12),
                Text("VIGIL CONNECT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 3)),
              ],
            ),
          ),
          body: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("WEARABLE STATUS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 25, letterSpacing: 6)),
                    if (errorMessage != null) Text("ERROR: $errorMessage"),

                    const SizedBox(height: 16),
                    _statusIndicator(),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("DEVICE ID:", style: TextStyle(fontSize: 20, letterSpacing: 2)),
                        SizedBox(width: 12),
                        Text(ble.deviceId.isNotEmpty ? ble.deviceId : "Unknown", style: TextStyle(fontSize: 20))
                      ],
                    ),

                    const SizedBox(height: 16),
                    if (lastUpload != null)
                      Text("Last Upload:   ${lastUpload!.toLocal()}", style: TextStyle(fontSize: 18)),
                    
                    const SizedBox(height: 16),
                    //Image.asset('assets/VIGIL_logo_white.png', width: 250, height: 250),
                    //const SizedBox(height: 16),

                    if (lastPacket != null)
                      Text(
                        "HR ${lastPacket!.heartRate.toStringAsFixed(0)}      |       "
                        "Temp ${lastPacket!.temp.toStringAsFixed(1)}°C       |       "
                        "Motion ${lastPacket!.motion.toStringAsFixed(1)}",
                        style: TextStyle(fontSize: 18),
                      ),
                    
                    const SizedBox(height: 32),

                    ElevatedButton(
                      onPressed: () async {
                        await sub?.cancel();
                        await ble.disconnect();
                        setState(() => status = CollectorStatus.idle);
                        _start();
                      },
                      child: const Text("RECONNECT", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    ),

                    if (status == CollectorStatus.error && errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 18),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),

              // DEBUG OVERLAY
              Positioned(
                top: 40,
                left: 10,
                child: Container(
                  color: Colors.black.withOpacity(0.7),
                  padding: const EdgeInsets.all(8),
                  child: Text("DEBUG: $status", style: const TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        );
    }
}