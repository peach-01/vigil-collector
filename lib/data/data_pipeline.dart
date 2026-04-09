import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:vigil_collector/logger.dart';
import 'package:vigil_collector/wearables/packet_cache.dart';
import 'sensor_packet.dart';
import 'uploader.dart';

class DataPipeline {
  final FirestoreUploader uploader;
  final String ownerId;
  final String wid;
  final bool isOrg;

  final Queue<SensorPacket> _queue = Queue();
  final List<SensorPacket> _batch = [];
  final PacketCache cache = PacketCache();

  Timer? _flushTimer;
  bool _uploading = false;

  static const int batchSize = 10;
  static const int maxQueueSize = 500;
  static const Duration flushInterval = Duration(seconds: 30);

  DataPipeline({required this.uploader, required this.ownerId, required this.wid, this.isOrg = false}) {
    _drainCacheOnStart();
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

      await uploader.uploadBatch(ownerId: ownerId, wid: wid, packets: List.from(_batch));
      _batch.clear();
    } catch (e) {
      if (kDebugMode) logStep("PIPELINE", "Upload FAILED, re-queueing: $e");
      await cache.addBatch(_batch);

      // delay before retrying
      await Future.delayed(const Duration(seconds: 2));

      // put back on front (offline-safe)
      _queue.addAll(_batch);
      _batch.clear();
    } finally {
      _uploading = false;
    }
  }

  Future<void> _drainCacheOnStart() async {
    if (await cache.hasData()) {
      final cached = await cache.drain();
      _queue.addAll(cached);
    }
  }

  void dispose() {
    _flushTimer?.cancel();
  }
}