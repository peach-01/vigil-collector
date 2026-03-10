import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'auth/auth_gate.dart';
import './firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // catch flutter framework errors
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // catch async / dart errors
    PlatformDispatcher.instance.onError = (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: true);
    }
    
  } catch (e) {
    debugPrint("Firebase init error");
  }
  runApp(const VigilCollectorApp());
}

/*void main() {
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text("TEST SCREEN"))),
    ),
  );
}*/

class VigilCollectorApp extends StatelessWidget {
  const VigilCollectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VIGIL Collect',
      theme: ThemeData.dark(),
      home: const AuthGate(),
    );
  }
}