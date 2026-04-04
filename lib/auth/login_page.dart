import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginPage extends StatefulWidget {
    const LoginPage({super.key});

    @override
    State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
    final email = TextEditingController();
    final password = TextEditingController();
    String error = "";

    Future<void> _login() async {
        try {
            await FirebaseAuth.instance.signInWithEmailAndPassword(
                email: email.text.trim(),
                password: password.text.trim(),
            );
        } catch (e) {
            setState(() => error = e.toString());
        }
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
          appBar: AppBar(
              title: Row(
                  children: [
                      Image.asset('assets/VIGIL_logo_white.png', width: 60, height: 60),
                      SizedBox(width: 12),
                      Text("VIGIL CONNECT", style: TextStyle(fontFamily: 'Michroma', fontSize: 18, letterSpacing: 3)),
                  ]
              )
          ),
          body: Center(
              child: SizedBox(
                  width: 320,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          Text('L O G I N', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, fontFamily: 'Michroma')),
                          const SizedBox(height: 35),

                          TextField(controller: email, decoration: const InputDecoration(labelText: 'Email', labelStyle: TextStyle(fontFamily: 'Jura', fontSize: 18))),
                          TextField(controller: password, decoration: const InputDecoration(labelText: 'Password', labelStyle: TextStyle(fontFamily: 'Jura', fontSize: 18)), obscureText: true),
                          const SizedBox(height: 20),
                          
                          ElevatedButton(onPressed: _login, child: const Text('L O G I N', style: TextStyle(fontFamily: 'Jura', fontSize: 14, fontWeight: FontWeight.bold))),
                          if (error.isNotEmpty) 
                              Text(error, style: const TextStyle(color: Colors.red, fontFamily: 'Jura', fontSize: 12)),
                      ],
                  ),
              ),
          ),
      );
    }
}
