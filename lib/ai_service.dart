import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
      throw Exception('No internet connection. Please check your network.');
    } catch (e) {
      debugPrint('🔴 Error: $e');
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
}

class Flashcard {
  final String question;
  final String answer;
  const Flashcard({required this.question, required this.answer});
}
