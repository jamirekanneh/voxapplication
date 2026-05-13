// lib/config/secrets.dart
//
// LLM keys are read from assets/project.env via flutter_dotenv.

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// OpenRouter API key for AiService.
/// Set `OPENROUTER_API_KEY` in [assets/project.env]. Empty string if missing.
String get kOpenRouterKey => (dotenv.env['OPENROUTER_API_KEY'] ?? '').trim();
