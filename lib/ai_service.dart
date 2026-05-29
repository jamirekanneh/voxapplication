import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'analytics_service.dart';
import 'custom_commands_provider.dart';
import 'voice_assistant_intent.dart';

// ignore: uri_does_not_exist
import 'config/secrets.dart';
import 'services/groq_service.dart';

class AiService {
  static const String _openRouterUrl =
      'https://openrouter.ai/api/v1/chat/completions';
  static const String _openRouterModel = 'meta-llama/llama-3.3-70b-instruct';
  static const String _groqUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _groqModel = 'llama-3.3-70b-versatile';
  static const int _maxChars = 12000;

  static Future<String> _callLlm(
    String systemPrompt,
    String userMessage, {
    double temperature = 0.9,
    int maxTokens = 2048,
  }) async {
    Object? lastError;

    if (kOpenRouterKey.isNotEmpty) {
      try {
        return await _postChatCompletion(
          provider: 'OpenRouter',
          url: _openRouterUrl,
          apiKey: kOpenRouterKey,
          model: _openRouterModel,
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          temperature: temperature,
          maxTokens: maxTokens,
          extraHeaders: const {
            'HTTP-Referer': 'https://voxapplication.app',
            'X-OpenRouter-Title': 'VoxApplication',
          },
        );
      } catch (e) {
        lastError = e;
        debugPrint('OpenRouter chat failed, trying Groq fallback: $e');
      }
    }

    if (kGroqApiKey.isNotEmpty) {
      try {
        return await _postChatCompletion(
          provider: 'Groq',
          url: _groqUrl,
          apiKey: kGroqApiKey,
          model: _groqModel,
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          temperature: temperature,
          maxTokens: maxTokens,
        );
      } catch (e) {
        lastError = e;
        debugPrint('Groq chat failed: $e');
      }
    }

    if (lastError != null) {
      final msg = lastError.toString().replaceFirst('Exception: ', '').trim();
      throw Exception(msg);
    }

    throw Exception(
      'No AI API key configured. Add OPENROUTER_API_KEY or GROQ_API_KEY to '
      'assets/project.env, then rebuild the app.',
    );
  }

  static Future<String> _postChatCompletion({
    required String provider,
    required String url,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userMessage,
    required double temperature,
    required int maxTokens,
    Map<String, String> extraHeaders = const {},
  }) async {
    final content = userMessage.length > _maxChars
        ? '${userMessage.substring(0, _maxChars)}\n\n[...trimmed...]'
        : userMessage;

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
              ...extraHeaders,
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': content},
              ],
              'max_tokens': maxTokens,
              'temperature': temperature,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        return _extractChatContent(response.body);
      }

      if (response.statusCode == 429) {
        throw Exception('Rate limit hit. Please wait 1 minute and try again.');
      }
      if (response.statusCode == 401) {
        throw Exception(
          'Invalid $provider API key. Check assets/project.env and rebuild.',
        );
      }

      final body = response.body.length > 300
          ? response.body.substring(0, 300)
          : response.body;
      throw Exception('Error ${response.statusCode}: $body');
    } on http.ClientException catch (e) {
      AnalyticsService.instance.recordApiError(
        provider,
        'Network Error: $e',
      );
      throw Exception('No internet connection. Please check your network.');
    } catch (e) {
      AnalyticsService.instance.recordApiError(provider, e.toString());
      rethrow;
    }
  }

  static String _extractChatContent(String responseBody) {
    final data = jsonDecode(responseBody);
    if (data is! Map<String, dynamic>) {
      throw Exception('AI returned an unexpected response format.');
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('AI returned no completion choices.');
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      throw Exception('AI returned an invalid message structure.');
    }
    final message = first['message'];
    if (message is! Map<String, dynamic>) {
      throw Exception('AI returned an empty message.');
    }
    final text = (message['content'] ?? '').toString().trim();
    if (text.isEmpty) {
      throw Exception('AI returned empty text.');
    }
    return text;
  }

  static String _prepareDocumentText(String documentText) {
    final trimmed = documentText.trim();
    if (trimmed.isEmpty) {
      throw Exception(
        'No text to analyze. Add document content or wait for a voice note transcript.',
      );
    }
    if (GroqService.isTranscriptPending(trimmed)) {
      throw Exception(
        'Transcript is not ready yet. Wait for transcription to finish, then try again.',
      );
    }
    if (trimmed.length < 20) {
      throw Exception(
        'Text is too short to summarize or generate Q&A (${trimmed.length} characters).',
      );
    }
    return trimmed;
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
          body: jsonEncode({'message': userMessage, 'assistant': 'vox'}),
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
    final text = _prepareDocumentText(documentText);
    const system =
        'You are an expert academic summarizer. '
        'Given a document, produce a clear summary with: '
        '1) A short overview paragraph, '
        '2) Key points each prefixed with "-", '
        '3) Important conclusions. '
        'Use plain text only and no markdown headers or bold.';
    return _callLlm(
      system,
      'Summarize this document:\n\n$text',
      temperature: 0.4,
      maxTokens: 4096,
    );
  }

  /// High-level semantic routing: maps STT transcript to structured app command.
  /// Returns null if the LLM request fails.
  static Future<VoiceAssistantInterpretation?> interpretVoiceAssistant({
    required String transcript,
    List<CustomCommand> customCommands = const [],
  }) async {
    final t = transcript.trim();
    if (t.isEmpty) return null;

    String customCommandsContext = '';
    if (customCommands.isNotEmpty) {
      final cmds = customCommands
          .map(
            (c) =>
                'ID: "${c.id}" => Phrase: "${c.phrase}" (Action: ${c.action.name})',
          )
          .join('\n');
      customCommandsContext =
          '\n\nThe user has configured these custom commands. '
          'If the speech asks to trigger one, output action="custom_command" and include '
          '"customCommandId": "<ID_HERE>".\nCustom Commands:\n$cmds\n';
    }

    final systemPrompt =
        'You classify short spoken phrases for the Vox mobile app voice assistant '
        '(navigation, searching files/notes, opening saved quizzes, playback control). '
        'Output only a single JSON object. No markdown, no prose, no trailing text. '
        'Schema strictly:\n'
        '{"action":"<ACTION>","query":null|String,"reply":null|String,"customCommandId":null|String}\n\n'
        '- action must be exactly one of: none, navigate_home, navigate_notes, '
        'navigate_menu, navigate_dictionary, search_library, search_notes, open_note, '
        'open_assessments, reading_play, reading_pause, reading_stop, reading_faster, '
        'reading_slower, assistant_off, custom_command.\n'
        '- Put user-specific text (search keywords, file/title hints) in query when relevant, otherwise null.\n'
        '- assistant_off means the user wants to stop the hands-free assistant.\n'
        '- reading_* means controlling text-to-speech while reading documents.\n'
        '- Understand synonyms ("take me home", "show my uploads", "open dictionary").\n'
        '- If speech is unrelated, use action=none with a short reply (14 words max, English).\n'
        '$customCommandsContext';

    try {
      final raw = await _callLlm(
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
        'You must give accurate answers based on these facts about the app: '
        '1) Sign In: The app uses passwordless Magic Link via email. '
        '2) Dictionary: Allows searching terms with General, Medical, and Technical dictionaries. '
        '3) Notes/Library: Users can upload documents (PDF/DOCX/Text/Scans). TTS can read them aloud. '
        '4) AI Study Buddy: Inside the reader, users can tap "Study Buddy" to chat with the document and ask questions about the text. '
        '5) Accessibility & Focus: Inside the reader settings (gear icon), users can toggle OpenDyslexic font and Bionic Reading focus mode. '
        '6) Reading Goals: Users can set a daily reading target in the Statistics page and track their Learning Streak. '
        '7) Voice Commands: Global hands-free control via STT. '
        'Keep answers friendly, concise, and do not invent features not listed here.';

    final nlpUrl = dotenv.env['NLP_API_URL']?.trim() ?? '';
    if (nlpUrl.isNotEmpty) {
      return _callNlpAssistant(userMessage).catchError((_) {
        return _callLlm(fallbackSystem, userMessage);
      });
    }
    return _callLlm(fallbackSystem, userMessage);
  }

  /// Generates [count] flashcards and returns parsed Q&A.
  static Future<List<Flashcard>> generateFlashcards(
    String documentText, {
    int count = 10,
  }) async {
    final text = _prepareDocumentText(documentText);
    final seed = Random().nextInt(99999);
    final safeCount = count.clamp(3, 30);

    final system =
        'You are a study flashcard generator. '
        'Output ONLY a JSON array with exactly $safeCount objects. '
        'No markdown, no code fences, no explanation. '
        'Each object must have string fields "question" and "answer". '
        'Example: [{"question":"What is X?","answer":"X is ..."}] '
        'Seed: $seed.';

    final raw = await _callLlm(
      system,
      'Create $safeCount flashcards from this document:\n\n$text',
      temperature: 0.5,
      maxTokens: 4096,
    );

    return _parseFlashcardsFromModel(raw, safeCount);
  }

  static List<Flashcard> _parseFlashcardsFromModel(String raw, int expectedMin) {
    var cleaned = raw.replaceAll(RegExp(r'```json|```', caseSensitive: false), '').trim();
    final start = cleaned.indexOf('[');
    final end = cleaned.lastIndexOf(']');
    if (start != -1 && end > start) {
      cleaned = cleaned.substring(start, end + 1);
    }

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is! List) {
        throw const FormatException('Expected JSON array');
      }
      final cards = <Flashcard>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final q = (item['question'] ?? item['q'] ?? '').toString().trim();
        final a = (item['answer'] ?? item['a'] ?? '').toString().trim();
        if (q.isNotEmpty && a.isNotEmpty) {
          cards.add(Flashcard(question: q, answer: a));
        }
      }
      if (cards.length >= 3) return cards;
      throw FormatException('Only ${cards.length} valid cards parsed');
    } catch (e) {
      debugPrint('Flashcard JSON parse error: $e');
      debugPrint('Raw model output: $raw');
      throw Exception(
        'Could not parse Q&A cards from the AI response. Tap Try Again.',
      );
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
