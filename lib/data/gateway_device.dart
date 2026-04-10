import 'package:vigil_collector/data/data_pipeline.dart';
import 'package:vigil_collector/data/sensor_packet.dart';
import 'package:vigil_collector/wearables/wearable_manager.dart';

class GatewayDevice {
  final WearableManager manager;
  final DataPipeline pipeline;

  // ---------------- CORE DATA ----------------

  SensorPacket? lastPacket;
  DateTime? lastUpload;
  WearableState state;

  String? assignedUserName;

  // ---------------- UI FIELDS ----------------
  DateTime connectedAt;
  int? batteryLevel;        // %
  int? rssi;                 // signal strength
  DateTime? lastSeen;       // last BLE activity

  String? statusNote;       // (optional) track disconnect reason/health

  GatewayDevice({
    required this.manager, 
    required this.pipeline, 
    this.state = WearableState.scanning,
    DateTime? connectedAt,
  }) : connectedAt = connectedAt ?? DateTime.now();

  // ---------------- HELPERS ----------------
  String get connectionDuration {
    final diff = DateTime.now().difference(connectedAt);
    if (diff.inMinutes < 1) return "${diff.inSeconds}s";
    if (diff.inHours < 1) return "${diff.inMinutes}m";
    return "${diff.inHours}h ${diff.inMinutes % 60}m";
  }

  String get lastUploadAgo {
    if (lastUpload == null) return "Never";
    final diff = DateTime.now().difference(lastUpload!);

    if (diff.inSeconds < 60) return "${diff.inSeconds}s ago";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    return "${diff.inHours}h ago";
  }

  String get signalQuality {
    if (rssi == null) return "Unknown";

    if (rssi! > -60) return "Excellent";
    if (rssi! > -70) return "Good";
    if (rssi! > -80) return "Fair";
    return "Weak";
  }

  bool get isConnected => state == WearableState.connected;
}