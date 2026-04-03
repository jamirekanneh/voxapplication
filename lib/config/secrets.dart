// lib/config/secrets.dart
//
// Environment-based configuration
// Values loaded from .env file (not committed to version control)
//
// Get your FREE Groq key from: https://console.groq.com
// Sign up → API Keys → Create API Key

import 'package:flutter_dotenv/flutter_dotenv.dart';

String get kGroqKey {
  final key = dotenv.env['GROQ_API_KEY'];
  if (key == null || key.isEmpty) {
    throw Exception('GROQ_API_KEY not found in .env file');
  }
  return key;
}
