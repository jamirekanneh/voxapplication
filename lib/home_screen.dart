import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("The Vox Home", style: TextStyle(color: Colors.black)),
        backgroundColor: const Color(0xFFF3E5AB),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              // Restart app or navigate back to splash
            },
          )
        ],
      ),
      body: const Center(
        child: Text(
          "Welcome to the Home Screen!\nYour student problems start solving here.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      ),
    );
  }
}