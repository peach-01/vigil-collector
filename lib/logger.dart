import 'package:flutter/foundation.dart';

void logStep(String tag, String msg) {
  final time = DateTime.now().toIso8601String();
  debugPrint("[$time][$tag] $msg");
}