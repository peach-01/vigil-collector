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

    Future<void> upload(SensorPacket packet, String wid) async {
        final res = await http.post(
            Uri.parse('$apiBase/data/upload'),
            headers: {
                "Authorization": "Bearer $token",
                "Content-Type": "application/json",
            },
            body: jsonEncode(packet.toJson(wid)),
        );

        if (res.statusCode != 200) {
            throw Exception(res.body);
        }
    }
}

class FirestoreUploader {
    final FirebaseFirestore _db;
    final Set<String> _registeredCache = {};

    String? _cachedName;
    String? _cachedOrgId;
    String? _lastCachedUid;

    DateTime? _lastStatusUpdate;
    

    FirestoreUploader({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

    // Uploads telemetry
    Future<void> _uploadTelemetry({required SensorPacket packet, required String wid}) async {
        final telemetryRef = _db.collection('wearables').doc(wid).collection('telemetry').doc();
        
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

        // Heartbeat update
        await _db.collection('wearables').doc(wid).set({
          'status': {
            'lastSeen': FieldValue.serverTimestamp(),
            'online': true,
            //'batteryPct': packet.batteryPct,
          }
        }, SetOptions(merge: true));
    }

    Future<void> uploadBatch({required String wid, required List<SensorPacket> packets, bool isOrg = false}) async {
      if (packets.isEmpty) return;

      final batch = _db.batch();
      final telemetryCol = _db.collection('wearables').doc(wid).collection('telemetry');

      if (_lastStatusUpdate == null || DateTime.now().difference(_lastStatusUpdate!) > Duration(seconds: 15)) {
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

        batch.set(_db.collection('wearables').doc(wid), {
          'status': {
            'online': true,
            'lastSeen': FieldValue.serverTimestamp(),
          }
        }, SetOptions(merge: true));
        await batch.commit();

        _lastStatusUpdate = DateTime.now();
      }

      // run danger detection on last sample only
      _evalRealtimeTelemetry(wid, packets.last);
    }

    Future<void> ingestTelemetry({required String wid, required SensorPacket packet}) async {
        _evalRealtimeTelemetry(wid, packet);    // realtime danger eval
        _uploadTelemetry(packet: packet, wid: wid);   // write telemetry
    }

    void _evalRealtimeTelemetry(String wid, SensorPacket packet) async {
      final wDoc = await _db.collection('wearables').doc(wid).get();
      final uid = wDoc.data()?['assignedTo'];
      if (uid == null) return;

      final hr = packet.heartRate;
      final hrv = packet.hrv;
      final temp = packet.temp;

      // Immediate Danger Thresholds (Conservative)
      if (hr >= 180) {
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

  // ---------- WEARABLE REGISTRY ----------
  Future<void> ensureWearableRegistered({required String wid, required String type, String? orgId}) async {         
    if (_registeredCache.contains(wid)) return;
    
    final ref = _db.collection('wearables').doc(wid);         
    final snap = await ref.get();

    if (snap.exists) {
      // already registered -> only ensure minimal field exists
      await ref.set({
        'wearableId': wid,
        'type': type,
        if (orgId != null) 'orgId': orgId,
        'status': {
          'lastSeen': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));
      return;
    }

    // first-time registry
    await ref.set({                 
      'wearableId': wid,                 
      'type': type,
      'orgId': orgId,
      'createdAt': FieldValue.serverTimestamp(),                 
      'status': {                     
        'active': true,                     
        'online': true,                     
        'batteryPct': 0,                     
        'lastSeen': FieldValue.serverTimestamp(),                 
      }             
    });

    _registeredCache.add(wid);
  }


  // ------------ WEARABLE ASSIGNMENT -----------
  Future<void> assignWearableToUser({required String wid, required String uid}) async {
    final batch = _db.batch();
    final wearableRef = _db.collection('wearables').doc(wid);
    final userRef = _db.collection('users').doc(uid);
    final userSnap = await userRef.get();
    final orgId = userSnap.data()?['orgId'];

    batch.set(wearableRef, {
      'assignedTo': uid,
      'orgId': orgId,
      'assignedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // user ref
    batch.set(userRef.collection('wearables').doc(wid), {
      'wearableId': uid,
      'assignedAt': FieldValue.serverTimestamp(),
      'active': true,
    }, SetOptions(merge: true));
    await batch.commit();
  }
}