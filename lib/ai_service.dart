import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'analytics_service.dart';
import 'voice_assistant_intent.dart';

// ignore: uri_does_not_exist
import 'config/secrets.dart';

class AiService {
  static const String _baseUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _model = 'llama-3.3-70b-versatile';
  static const int _maxChars = 12000;

  static Future<String> _callGroq(
    String systemPrompt,
    String userMessage, {
    double temperature = 0.9,
    int maxTokens = 2048,
  }) async {
    if (kGroqKey.isEmpty) {
      throw Exception(
        'Missing GROQ_API_KEY. Edit assets/project.env, add your key from '
        'https://console.groq.com, then rebuild the app.',
      );
    }
    debugPrint('🌐 Calling Groq API...');

    final content = userMessage.length > _maxChars
        ? '${userMessage.substring(0, _maxChars)}\n\n[...trimmed...]'
        : userMessage;

    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $kGroqKey',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': content},
              ],
              'max_tokens': maxTokens,
              'temperature': temperature,
            }),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List<dynamic>;
        return (choices.first as Map<String, dynamic>)['message']['content']
            as String;
      } else if (response.statusCode == 429) {
        throw Exception('Rate limit hit — please wait 1 minute and try again.');
      } else if (response.statusCode == 401) {
        throw Exception(
          'Invalid Groq API key. Check GROQ_API_KEY in assets/project.env.',
        );
      } else {
        final body = response.body.length > 300
            ? response.body.substring(0, 300)
            : response.body;
        debugPrint('🔴 Error body: ${response.body}');
        throw Exception('Error ${response.statusCode}: $body');
      }
    } on http.ClientException catch (e) {
      debugPrint('🔴 Network error: $e');
      AnalyticsService.instance.recordApiError('Groq', 'Network Error: $e');
      throw Exception('No internet connection. Please check your network.');
    } catch (e) {
      debugPrint('🔴 Error: $e');
      AnalyticsService.instance.recordApiError('Groq', e.toString());
      rethrow;
    }
  }

  static Future<String> _callNlpAssistant(String userMessage) async {
    final apiUrl = dotenv.env['NLP_API_URL']?.trim() ?? '';
    final apiKey = dotenv.env['NLP_API_KEY']?.trim() ?? '';

    if (apiUrl.isEmpty) {
      throw Exception('NLP API is not configured. Missing NLP_API_URL.');
    }

    final response = await http
        .post(
          Uri.parse(apiUrl),
          headers: {
            'Content-Type': 'application/json',
            if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'message': userMessage,
            'assistant': 'vox',
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('NLP API error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic>) {
      final text = (data['reply'] ?? data['response'] ?? data['text'] ?? '')
          .toString()
          .trim();
      if (text.isNotEmpty) return text;
    }

    throw Exception('NLP API returned an empty response.');
  }

  /// Summarizes the document and returns plain-text summary.
  static Future<String> summarize(String documentText) {
    const system =
        'You are an expert academic summarizer. '
        'Given a document, produce a clear summary with: '
        '1) A short overview paragraph, '
        '2) Key points each prefixed with "•", '
        '3) Important conclusions. '
        'Use plain text only — no markdown headers or bold.';
    return _callGroq(system, 'Summarize this document:\n\n$documentText');
  }

  /// High-level semantic routing: maps device STT transcript → structured app command.
  /// Returns null if the Groq request fails — caller falls back to local phrase matching.
  static Future<VoiceAssistantInterpretation?> interpretVoiceAssistant({
    required String transcript,
  }) async {
    final t = transcript.trim();
    if (t.isEmpty) return null;

    const systemPrompt =
        'You classify short spoken phrases for the Vox mobile app voice assistant '
        '(navigation, searching files/notes, opening saved quizzes, playback control). '
        'Output ONLY a single JSON object. No markdown, no prose, no trailing text. '
        'Schema strictly:\n'
        '{"action":"<ACTION>","query":null|String,"reply":null|String}\n\n'
        '- action must be exactly one of: none, navigate_home, navigate_notes, '
        'navigate_menu, navigate_dictionary, search_library, search_notes, open_note, '
        'open_assessments, reading_play, reading_pause, reading_stop, reading_faster, '
        'reading_slower, assistant_off.\n'
        '- Put user-specific text (search keywords, file/title hints) in query when '
        'relevant otherwise null.\n'
        '- assistant_off: user wants quiet or to stop hands-free assistant.\n'
        '- reading_*: controlling text-to-speech while reading documents.\n'
        '- Understand synonyms ("take me home", "show my uploads", '
        '"open dictionary", etc.) and multilingual phrasing.\n'
        '- If speech is unrelated to Vox navigation/search/playback, '
        'action=none with a short reply (≤14 words English) naming one example phrase.\n';

    try {
      final raw = await _callGroq(
        systemPrompt,
        'User spoke:\n"""$t"""',
        temperature: 0.12,
        maxTokens: 256,
      );
      final jsonStr = _extractJsonObject(raw);
      if (jsonStr == null) return null;
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) return null;
      return VoiceAssistantInterpretation.tryParse(decoded);
    } catch (e, st) {
      debugPrint('interpretVoiceAssistant: $e\n$st');
      return null;
    }
  }

  static String? _extractJsonObject(String text) {
    final s = text.trim();
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    return s.substring(start, end + 1);
  }

  /// Assistant for generic questions.
  static Future<String> askAssistant(String userMessage) {
    const fallbackSystem =
        'You are Vox Assistant, an AI helper for the Vox app. '
        'You MUST give accurate answers based on these facts about the app: '
        '1) Sign In: The app uses passwordless Magic Link via email. '
        '2) Dictionary: Allows searching terms with General, Medical, and Technical dictionaries. '
        '3) Notes/Library: Users can upload documents (PDF/DOCX/Text/Scans). TTS (Text-to-Speech) can read them aloud. '
        '4) AI Study Buddy: Inside the reader, users can tap "Study Buddy" to chat with the document and ask questions about the text. '
        '5) Accessibility & Focus: Inside the reader settings (gear icon), users can toggle OpenDyslexic font and Bionic Reading focus mode. '
        '6) Reading Goals: Users can set a daily reading target (minutes) in the Statistics page and track their Learning Streak. '
        '7) Voice Commands: Global hands-free control via STT. '
        'Please keep answers very friendly, concise, and do not invent new features not mentioned here.';

    return _callNlpAssistant(userMessage).catchError((_) {
      return _callGroq(fallbackSystem, userMessage);
    });
  }

  /// Generates [count] flashcards — different every time due to random seed in prompt.
  static Future<List<Flashcard>> generateFlashcards(
    String documentText, {
    int count = 10,
  }) async {
    // Random seed in prompt ensures different questions every call
    final seed = Random().nextInt(99999);

    final system =
        'You are a creative study flashcard generator. '
        'Generate exactly $count unique flashcards covering important concepts. '
        'Every time you are called, generate DIFFERENT questions — vary the focus, angle, and phrasing. '
        'Seed for variation: $seed. '
        'Respond ONLY with a valid JSON array — no markdown fences, no explanation, nothing else. '
        'Format: [{"question":"...","answer":"..."}, ...]';

    final raw = await _callGroq(
      system,
      'Generate $count flashcards from this document:\n\n$documentText',
    );

    final cleaned = raw.replaceAll(RegExp(r'```json|```'), '').trim();

    try {
      final parsed = jsonDecode(cleaned) as List<dynamic>;
      return parsed
          .map(
            (e) => Flashcard(
              question: (e as Map<String, dynamic>)['question'] as String,
              answer: e['answer'] as String,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('🔴 JSON parse error: $e');
      debugPrint('🔴 Raw response: $cleaned');
      throw Exception('Could not parse flashcards. Please try again.');
    }
  }

  /// Provides guidance on how to use the Vox app.
  static Future<String> helpUser(String userQuery) {
    return askAssistant(userQuery);
  }
}

class Flashcard {
  final String question;
  final String answer;
  const Flashcard({required this.question, required this.answer});
}
