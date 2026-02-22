import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // Import the file we just generated
import 'splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // This uses the generated file to pick the right keys automatically
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("Firebase connected successfully!");
  } catch (e) {
    print("Error connecting to Firebase: $e");
  }

  runApp(const TheVoxApp());
}

class TheVoxApp extends StatelessWidget {
  const TheVoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(), // Your yellow splash screen
    );
  }
}