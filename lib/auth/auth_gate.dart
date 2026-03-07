import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../ui/connect_wearable_page.dart';
import 'login_page.dart';

class AuthGate extends StatelessWidget {
    const AuthGate({super.key});

    @override
    Widget build(BuildContext context) {
        return StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snap) {
                if (!snap.hasData) return const LoginPage();
                return ConnectWearablePage(uid: snap.data!.uid);
            },
        );
    }
}