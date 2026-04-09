import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/sensor_packet.dart';

class PacketCache {
  static const _key = "packet_cache";

  Future<void> addBatch(List<SensorPacket> packets) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];

    for (final p in packets) {
      list.add(jsonEncode(p.toJson("offline")));
    }

    await prefs.setStringList(_key, list);
  }

  Future<List<SensorPacket>> drain() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];

    await prefs.remove(_key);

    return list.map((e) => SensorPacket.fromJson(jsonDecode(e))).toList();
  }

  Future<bool> hasData() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? []).isNotEmpty;
  }
}