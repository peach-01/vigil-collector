import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:vigil_collector/logger.dart';
import 'sensor_packet.dart';
import 'uploader.dart';

class DataPipeline {
  final FirestoreUploader uploader;
  final String uid;
  final String wid;

  final Queue<SensorPacket> _queue = Queue();
  final List<SensorPacket> _batch = [];

  Timer? _flushTimer;
  bool _uploading = false;

  static const int batchSize = 10;
  static const int maxQueueSize = 500;
  static const Duration flushInterval = Duration(seconds: 30);

  DataPipeline({required this.uploader, required this.uid, required this.wid}) {
    _startAutoFlush();
  }

  void add(SensorPacket packet) {
    if (_queue.length >= maxQueueSize) {
      _queue.removeFirst();   // prevents infinite memory growth
    }
    _queue.add(packet);
  }

  void _startAutoFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(flushInterval, (_) => flush());
  }

  Future<void> flush() async {
    if (_uploading || _queue.isEmpty) return;
    _uploading = true;

    try {
      while (_queue.isNotEmpty && _batch.length < batchSize) {
        _batch.add(_queue.removeFirst());
      }

      if (_batch.isEmpty) return;

      await uploader.uploadBatch(uid: uid, wid: wid, packets: List.from(_batch));
      _batch.clear();
    } catch (e) {
      if (kDebugMode) logStep("PIPELINE", "Upload FAILED, re-queueing: $e");

      // delay before retrying
      await Future.delayed(const Duration(seconds: 2));

      // put back on front (offline-safe)
      _queue.addAll(_batch);
      _batch.clear();
    } finally {
      _uploading = false;
    }
  }

  void dispose() {
    _flushTimer?.cancel();
  }
}