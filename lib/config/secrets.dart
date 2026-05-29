// lib/config/secrets.dart
//
// LLM keys are read from assets/project.env via flutter_dotenv.

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// OpenRouter API key for AiService (chat, summarize, flashcards).
String get kOpenRouterKey => (dotenv.env['OPENROUTER_API_KEY'] ?? '').trim();

/// Groq API key — transcription; also used for chat if OpenRouter is unset.
String get kGroqApiKey => (dotenv.env['GROQ_API_KEY'] ?? '').trim();

bool get kHasChatApiKey => kOpenRouterKey.isNotEmpty || kGroqApiKey.isNotEmpty;
