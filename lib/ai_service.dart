import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'analytics_service.dart';

// ignore: uri_does_not_exist
import 'config/secrets.dart';

class AiService {
  static const String _baseUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _model = 'llama-3.3-70b-versatile';
  static const int _maxChars = 12000;

  static Future<String> _callGroq(
    String systemPrompt,
    String userMessage,
  ) async {
    debugPrint('🔑 Groq key loaded: ${kGroqKey.length} chars');
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
              'max_tokens': 2048,
              'temperature': 0.9, // Higher = more varied responses each time
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
          'Invalid API key. Please check your Groq key in secrets.dart',
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

  /// Assistant for generic questions.
  static Future<String> askAssistant(String userMessage) {
    const system =
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
    return _callGroq(system, userMessage);
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
    const system =
        'You are the Vox App Assistant, a premium AI guide for the Vox Application. '
        'The Vox app features include:\n'
        '- AI Study Buddy: Chat with your documents in real-time while listening.\n'
        '- Accessibility: OpenDyslexic font and Bionic Reading focus mode in the reader settings.\n'
        '- Dictionary: Search for General, Medical, and Technical terms.\n'
        '- Notes/Library: Organize documents, summarize them, and create AI flashcards.\n'
        '- Statistics: Track your daily reading goals and learning streaks.\n'
        '- Voice Commands: Control everything hands-free.\n'
        'Keep your responses modern, concise, and helpful. Use a friendly yet professional tone.';
    return _callGroq(system, userQuery);
  }
}

class Flashcard {
  final String question;
  final String answer;
  const Flashcard({required this.question, required this.answer});
}
