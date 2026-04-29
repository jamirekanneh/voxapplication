import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseDiagnosticResult {
  final String name;
  final bool success;
  final String message;

  FirebaseDiagnosticResult({
    required this.name,
    required this.success,
    required this.message,
  });
}

Future<List<FirebaseDiagnosticResult>> runFirebaseDiagnostics() async {
  final List<FirebaseDiagnosticResult> results = [];

  // 1. Firebase Initialization
  try {
    final firebaseApp = Firebase.app();
    results.add(FirebaseDiagnosticResult(
      name: 'Firebase Initialization',
      success: true,
      message: 'Firebase initialized with app: ${firebaseApp.name}',
    ));
  } catch (e) {
    results.add(FirebaseDiagnosticResult(
      name: 'Firebase Initialization',
      success: false,
      message: 'Failed to initialize Firebase: $e',
    ));
    return results; // Cannot continue if Firebase isn't initialized
  }

  // 2. Auth Status
  try {
    final user = FirebaseAuth.instance.currentUser;
    results.add(FirebaseDiagnosticResult(
      name: 'Firebase Auth',
      success: true,
      message: user != null ? 'Authenticated as: ${user.email ?? 'Anonymous'}' : 'Not authenticated',
    ));
  } catch (e) {
    results.add(FirebaseDiagnosticResult(
      name: 'Firebase Auth',
      success: false,
      message: 'Auth check failed: $e',
    ));
  }

  // 3. Firestore Connectivity
  try {
    await FirebaseFirestore.instance.collection('health_check').doc('ping').get().timeout(const Duration(seconds: 5));
    results.add(FirebaseDiagnosticResult(
      name: 'Firestore Connectivity',
      success: true,
      message: 'Successfully reached Firestore',
    ));
  } catch (e) {
    results.add(FirebaseDiagnosticResult(
      name: 'Firestore Connectivity',
      success: false,
      message: 'Firestore check failed: $e',
    ));
  }

  return results;
}
