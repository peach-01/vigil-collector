import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'auth/auth_gate.dart';
import './firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  //debugPrint("BOOT_TRACE: Flutter binding initialized");

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  //debugPrint("BOOT_TRACE: Firebase initialized");

  // catch flutter framework errors
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // catch async / dart errors
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  
  runApp(const VigilCollectorApp());
}

class VigilCollectorApp extends StatelessWidget {
  const VigilCollectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    //debugPrint("BOOT_TRACE: MaterialApp build started");

    return MaterialApp(
      title: 'VIGIL Collect',
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
    );
  }
}