import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'auth/auth_gate.dart';
import './firebase_options.dart';

/*void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase init error");
  }
  runApp(const VigilCollectorApp());
}*/

void main() {
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text("TEST SCREEN"))),
    ),
  );
}

class VigilCollectorApp extends StatelessWidget {
  const VigilCollectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VIGIL Collector',
      theme: ThemeData.dark(),
      home: const AuthGate(),
    );
  }
}