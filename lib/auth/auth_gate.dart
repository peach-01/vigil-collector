import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../ui/connect_wearable_page.dart';
import '../logger.dart';
import 'login_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        logStep("AUTH", "ConnectionState: ${snap.connectionState}");
        logStep("AUTH", "HasData: ${snap.hasData}");
        logStep("AUTH", "User: ${snap.data?.uid}");

        if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: Text("AUTH: WAITING")));
        if (snap.hasError) return Scaffold(body: Center(child: Text("AUTH ERROR: ${snap.error}")));        
        if (!snap.hasData) return const LoginPage();
        
        logStep("AUTH", "Navigating to ConnectWearablePage");
        
        return ConnectWearablePage(uid: snap.data!.uid);
      },
    );
  }
}