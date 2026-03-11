import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'auth/auth_gate.dart';
import './firebase_options.dart';

/*void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("Flutter binding initialized");

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("Firebase initialized successfully");
  } catch (e, stack) {
    debugPrint("Firebase initialization failed: $e");
    debugPrint("$stack");
  }

  // catch flutter framework errors
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // catch async / dart errors
  PlatformDispatcher.instance.onError = (e, stack) {
    FirebaseCrashlytics.instance.recordError(e, stack, fatal: true);
    return true;
  };

  runZonedGuarded(() {
    debugPrint("Running VigilCollectorApp");
    runApp(const VigilCollectorApp());
  }, (e, stack) {
    FirebaseCrashlytics.instance.recordError(e, stack, fatal: true);
  });
}*/

void bootLog(String message) {
  debugPrint("BOOT_TRACE: $message");
  FirebaseCrashlytics.instance.log("BOOT_TRACE: $message");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bootLog("Flutter binding initialized");

  await runZonedGuarded(() async {

    bootLog("Initializing Firebase");
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    bootLog("Firebase initialized");

    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    FirebaseCrashlytics.instance.log("FLUTTER_BOOT: runApp starting");

    runApp(const StartupTracerApp());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      bootLog("First Flutter frame rendered");
    });

  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

class StartupTracerApp extends StatefulWidget {
  const StartupTracerApp({super.key});

  @override
  State<StartupTracerApp> createState() => _StartupTracerAppState();
}

class _StartupTracerAppState extends State<StartupTracerApp> {
  String step = "Starting app...";

  @override
  void initState() {
    super.initState();
    startBoot();
  }

  Future<void> startBoot() async {
    try {
      setStep("Step 1: Flutter engine started");
      await Future.delayed(const Duration(seconds: 1));

      setStep("Step 2: Initializing Firebase");
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      setStep("Step 3: Firebase initialized");
      await Future.delayed(const Duration(seconds: 1));

      setStep("Step 4: Launching main app");
      await Future.delayed(const Duration(seconds: 1));

      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const VigilCollectorApp(),
          ),
        );
      });
      
    } catch (e, stack) {
      setStep("ERROR during startup:\n$e");
      debugPrintStack(stackTrace: stack);
    }
  }

  void setStep(String newStep) {
    debugPrint(newStep);
    FirebaseCrashlytics.instance.log(newStep);

    setState(() {
      step = newStep;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Startup Debug",
      home: Scaffold(
        backgroundColor: Colors.red,
        body: Center(
          child: Text(
            step,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class VigilCollectorApp extends StatelessWidget {
  const VigilCollectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    bootLog("MaterialApp build started");
    return MaterialApp(
      title: 'VIGIL Collect',
      theme: ThemeData.dark(),
      home: const AuthGate(),
      builder: (context, child) {
        bootLog("First frame builder executed");
        return child!;
      },
    );
  }
}