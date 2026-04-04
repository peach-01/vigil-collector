import 'package:shared_preferences/shared_preferences.dart';

class WearableStorage {
  static const _key = "paired_device_id";
  static const _last = "last_device";

  static Future<void> save(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
  }

  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> saveLastDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_last, id);
  }

  static Future<String?> getLastDevice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_last);
  }
}