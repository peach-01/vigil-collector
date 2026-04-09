import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vigil_collector/logger.dart';
import 'package:vigil_collector/ui/org_gateway_page.dart';

import '../ui/connect_page.dart';
import 'login_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<String> _getRole(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection("roles").doc(uid).get();
      final data = doc.data();
      return data?["role"] ?? "user";
    } catch (e) {
      logStep("AUTH", "Error loading role data: $e");
      return "user";    // fallback to user role
    }
    
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (snap.hasError) return Scaffold(body: Center(child: Text("AUTH ERROR: ${snap.error}")));        
        if (!snap.hasData) return const LoginPage();

        final uid = snap.data!.uid;
        logStep("AUTH", "uid: $uid");

        return FutureBuilder<String>(
          future: _getRole(uid), 
          builder: (context, roleSnap) {
            if (roleSnap.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            if (roleSnap.hasError) return Scaffold(body: Center(child: Text("Error loading role: ${roleSnap.error}")));
            if (!roleSnap.hasData) return const Scaffold(body: Center(child: Text("Role data not found")));

            final role = roleSnap.data ?? "user";
            
            if (role == "org") {
              return OrgGatewayPage(orgId: uid);
            }
            return ConnectWearablePage(uid: uid);   // default - individual flow
          },
        );
      },
    );
  }
}