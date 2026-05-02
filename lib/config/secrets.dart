// lib/config/secrets.dart
//
// Groq and related keys are read from assets/project.env via flutter_dotenv.

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Groq API key for AiService (see https://console.groq.com → API Keys).
/// Set `GROQ_API_KEY` in [assets/project.env]. Empty string if missing.
String get kGroqKey => (dotenv.env['GROQ_API_KEY'] ?? '').trim();
