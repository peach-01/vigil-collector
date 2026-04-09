import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vigil_collector/logger.dart';
import 'sensor_packet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VigilUploader {
    final String apiBase;
    final String token;

    VigilUploader(this.apiBase, this.token);

    Future<void> upload(SensorPacket packet, String uid) async {
        final res = await http.post(
            Uri.parse('$apiBase/data/upload'),
            headers: {
                "Authorization": "Bearer $token",
                "Content-Type": "application/json",
            },
            body: jsonEncode(packet.toJson(uid)),
        );

        if (res.statusCode != 200) {
            throw Exception(res.body);
        }
    }
}

class FirestoreUploader {
    final FirebaseFirestore _db;
    String? _cachedName;
    String? _cachedOrgId;
    String? _lastCachedUid;

    FirestoreUploader({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

    // Registers a wearable to user
    Future<void> registerWearable({required String uid, required String wearableId, required String type}) async {
        final userSnap = await _db.collection('users').doc(uid).get();
        final String? orgId = userSnap.data()?['orgId'];

        final WriteBatch batch = _db.batch();
        
        // Global wearable record
        batch.set(
            _db.collection('wearables').doc(wearableId),
            {
                'wearableId': wearableId,
                'orgId': orgId,
                'type': type,
                'assignedTo': uid,
                'pairedAt': FieldValue.serverTimestamp(),
                'status': {
                    'active': true,
                    'online': true,
                    'batteryPct': 0,
                    'lastSeen': FieldValue.serverTimestamp(),
                }
            }, 
            SetOptions(merge: true),
        );

        // User-scoped wearable reference
        batch.set(
            _db.collection('users').doc(uid).collection('wearables').doc(wearableId),
            {
                'wearableId': wearableId,
                'type': type,
                'pairedAt': FieldValue.serverTimestamp(),
                'active': true,
            }, 
            SetOptions(merge: true),
        );

        await batch.commit();
    }

    // Uploads telemetry
    Future<void> _uploadTelemetry({required SensorPacket packet, required String uid, required String wearableId}) async {
        final telemetryRef = _db.collection('users').doc(uid).collection('wearables').doc(wearableId).collection('telemetry').doc();
        
        final upload = {
            'ts': FieldValue.serverTimestamp(),
            'heartRate': packet.heartRate,
            'hrv': packet.hrv,
            'temp': packet.temp,
            'motion': packet.motion,
            'sleepQuality': packet.sleepQuality,
            'sleepTime': packet.sleepTime,
        };

        // creates new telemetry upload
        await telemetryRef.set(upload);

        // updates the user's latest metrics
        await _db.collection('users').doc(uid).set({"latestMetrics": upload}, SetOptions(merge: true));

        // Heartbeat update
        await _db.collection('wearables').doc(wearableId).set({
          'status': {
            'lastSeen': FieldValue.serverTimestamp(),
            //'batteryPct': packet.batteryPct,
            'online': true,    
          }
        }, SetOptions(merge: true));
    }

    Future<void> uploadBatch({required String ownerId, required String wid, required List<SensorPacket> packets, bool isOrg = false}) async {
      if (packets.isEmpty) return;

      final base = isOrg ? _db.collection('orgs').doc(ownerId) : _db.collection('users').doc(ownerId);
      final batch = _db.batch();
      final telemetryCol = base.collection('wearables').doc(wid).collection('telemetry');

      for (final p in packets) {
        final ref = telemetryCol.doc();

        batch.set(ref, {
          'ts': FieldValue.serverTimestamp(),
          'heartRate': p.heartRate,
          'hrv': p.hrv,
          'temp': p.temp,
          'motion': p.motion,
          'sleepQuality': p.sleepQuality,
          'sleepTime': p.sleepTime,
        });
      }

      final last = packets.last;

      // single update
      batch.set(_db.collection('users').doc(ownerId), {
        'latestMetrics': {
          'ts': FieldValue.serverTimestamp(),
          'heartRate': last.heartRate,
          'hrv': last.hrv,
          'temp': last.temp,
          'motion': last.motion,
          'sleepQuality': last.sleepQuality,
          'sleepTime': last.sleepTime,
        }
      }, SetOptions(merge: true));
      batch.set(_db.collection('wearables').doc(wid), {
        'status': {
          'online': true,
          'lastSeen': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));
      await batch.commit();

      // run danger detection on last sample only
      _evalRealtimeTelemetry(ownerId, wid, last);
    }

    Future<void> ingestTelemetry({required String uid, required String wid, required SensorPacket packet}) async {
        // realtime danger eval
        _evalRealtimeTelemetry(uid, wid, packet);

        // write telemetry
        _uploadTelemetry(packet:packet, uid:uid, wearableId:wid);
    }

    void _evalRealtimeTelemetry(String uid, String wid, SensorPacket packet) {
        final hr = packet.heartRate;
        final hrv = packet.hrv;
        final temp = packet.temp;

        // Immediate Danger Thresholds (Conservative)
        if (hr >= 200) {
            _emitNotification(uid:uid, wid:wid, atype:"tachycardia", severity:"critical", msg:"Dangerously high heart rate", immediate:true);
        }
        if (hrv > 0 && hrv < 15) {
            _emitNotification(uid:uid, wid:wid, atype:"autonomic_collapse", severity:"critical", msg:"Severe HRV suppression", immediate:true);
        }
        if (temp >= 39) {
            _emitNotification(uid:uid, wid:wid, atype:"heat_stroke_risk", severity:"critical", msg:"POSSIBLE HEAT STROKE - immediate cooling required", immediate:true);
        } else if (temp >= 38.5) {
            _emitNotification(uid:uid, wid:wid, atype:"heat_danger", severity:"critical", msg:"Dangerous body temperature detected", immediate:true);
        } else if (temp >= 38) {
            _emitNotification(uid:uid, wid:wid, atype:"heat_warning", severity:"warning", msg:"Elevated core temperature", immediate:true);
        }
    }

    Future<void> _emitNotification({required String uid, required String wid, required String atype, required String severity, required String msg, bool immediate=false}) async {
        String? orgId = _cachedOrgId;
        String name = _cachedName ?? uid;

        if (_lastCachedUid != uid || _cachedOrgId == null || _cachedName == null) {
            try {
                final userDoc = await _db.collection("users").doc(uid).get();
                final data = userDoc.data();
                
                orgId = data?["orgId"];
                name = data?["profile"]?["name"] ?? uid;

                // update cache
                _cachedName = name;
                _cachedOrgId = orgId;
                _lastCachedUid = uid;
            } catch (e) {
              if (kDebugMode) logStep("UPLOAD", "Error fetching user orgId: $e");
              name = uid;
            }
        }

        final Map<String, dynamic> payload = {
            "type": atype,
            "severity": severity,
            "message": msg,
            "uid": uid,
            "name": name,
            "wearableId": wid,
            "immediate": immediate,
            "source": "system",
            "ts": FieldValue.serverTimestamp(),
            "read": false,
            "verified": false,
            "verificationOutcome": "",
            "verifiedBy": "",
        };

        // User Notification
        final WriteBatch batch = _db.batch();

        final userNotiRef = _db.collection("notifications").doc();
        batch.set(userNotiRef, {
            ...payload,
            "to": uid,
        });

        // Org Notification
        if (orgId != null && orgId.isNotEmpty) {
            final orgNotiRef = _db.collection("notifications").doc();
            batch.set(orgNotiRef, {
                ...payload,
                "to": orgId,
            });
        }
        
        // execute writes
        try {
            await batch.commit();
        } catch (e) {
          if (kDebugMode) logStep("UPLOAD", "Failed to emit notifications: $e");
        }
    }
}