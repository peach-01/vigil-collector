import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vigil_collector/ui/org_gateway_page.dart';

import '../ui/connect_page.dart';
import 'login_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<Map<String, dynamic>?> _loadUser(String uid) async {
    final doc = await FirebaseFirestore.instance.collection("users").doc(uid).get();
    return doc.data();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {

        if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: Text("AUTH: WAITING")));
        if (snap.hasError) return Scaffold(body: Center(child: Text("AUTH ERROR: ${snap.error}")));        
        if (!snap.hasData) return const LoginPage();

        final uid = snap.data!.uid;
                
        return FutureBuilder(
          future: _loadUser(uid), 
          builder: (context, userSnap) {
            if (!userSnap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));

            final data = userSnap.data!;
            final role = data["role"] ?? "user";
            final orgId = data["orgId"];

            if (role == "org" && orgId != null) {
              return OrgGatewayPage(orgId: orgId);
            }

            // default - individual flow
            return ConnectWearablePage(uid: uid);
          },
        );
      },
    );
  }
}