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
import 'services/document_language_service.dart';

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

  static String _outputLanguageInstruction(String outputLanguage) {
    if (outputLanguage == 'English') {
      return 'Write the entire response in English.';
    }
    return 'Write the entire response in $outputLanguage. '
        'If the source document is in that language, preserve its terminology.';
  }

  /// Summarizes the document and returns plain-text summary.
  static Future<String> summarize(
    String documentText, {
    String outputLanguage = 'English',
  }) {
    final text = _prepareDocumentText(documentText);
    final lang = _outputLanguageInstruction(outputLanguage);
    final system =
        'You are an expert academic summarizer. $lang '
        'Given a document, produce a clear summary with: '
        '1) A short overview paragraph, '
        '2) Key points as separate lines (one idea per line — do NOT use lone "-" or bullet-only lines), '
        '3) Important conclusions. '
        'Use plain text only — no markdown, headers, or bold.';
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
    String fallbackLanguage = 'English',
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

    final spokenLang = DocumentLanguageService.detectSpokenLanguageName(
      t,
      fallback: fallbackLanguage,
    );
    final replyLangRule = spokenLang == 'English'
        ? 'If speech is unrelated, use action=none with a short reply in English (14 words max).'
        : 'If speech is unrelated, use action=none with a short reply in $spokenLang (14 words max). '
            'For navigation or playback actions, set reply to null — the app speaks localized feedback.';

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
        '- Understand synonyms in any language ("take me home", "افتح القاموس", "abrir diccionario").\n'
        '- $replyLangRule\n'
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
  static Future<String> askAssistant(
    String userMessage, {
    String fallbackLanguage = 'English',
  }) {
    final responseLang = DocumentLanguageService.detectSpokenLanguageName(
      userMessage,
      fallback: fallbackLanguage,
    );
    final langRule = _outputLanguageInstruction(responseLang);

    final fallbackSystem =
        'You are Vox Assistant, an AI helper for the Vox mobile app. '
        '$langRule If the user writes in another language, reply in that language. '
        'Answer only from these facts. Be friendly, concise, and do not invent features.\n\n'
        'NAVIGATION: Home (library/uploaded files), Notes (voice notes + transcripts), '
        'Dictionary, Menu, Upload (+ center button), History.\n\n'
        'SIGN IN: Passwordless magic link by email. Known devices can open Home quickly; '
        'guest mode stores data locally only.\n\n'
        'HOME: Library of uploaded PDFs/DOCX/scans with folders and text search. '
        'Tap the mic in the search bar for voice search (pauses the hands-free Assistant). '
        'Enable Assistant on Home for navigation commands like "open notes" or "open dictionary". '
        'Double-tap anywhere for voice commands when Assistant is on.\n\n'
        'NOTES: Record voice notes, auto-transcribe, edit transcripts, play audio, '
        'TTS read-aloud, Summarize, Q&A Generator, and Study Buddy chat about the transcript. '
        'Save transcripts to Saved Docs when signed in.\n\n'
        'DICTIONARY: General, Medical, and Technical lookups; type or use the search-bar mic. '
        'Voice commands can open dictionary with a search term.\n\n'
        'READER: Open a file from Home to read with TTS. Study Buddy asks questions about the document. '
        'Summarize and Q&A Generator. OpenDyslexic and Bionic Reading in reader settings. '
        'VOICE WHILE READING: While a document is read aloud, say pause, play, continue, stop, forward, or back. '
        'The mic listens automatically during read-aloud. For best results use wired or Bluetooth earphones — '
        'audio goes to the earphones and the mic hears only your voice. On the phone speaker alone, voice control '
        'may miss commands or sound quiet because the app lowers read-aloud volume to hear you; earphones fix that.\n\n'
        'MENU: Profile, Language, Theme, Statistics (XP, levels, achievements, reading streaks), '
        'Reminders (schedule phone notifications to study a library file or note), '
        'Saved Docs (cloud summaries, Q&A sets, saved note transcripts with search and export), '
        'Recommendations, About, FAQs (this chat), Contact, Recycle Bin (restore deleted notes, '
        'recordings, uploads), Logout.\n\n'
        'FAQs PAGE & MENU CHATBOT: Floating "?" button opens Vox Assistant for app help.\n\n'
        'RECYCLE BIN: Restore deleted notes, recordings, and uploads—not voice commands.\n\n'
        'STATISTICS: Track usage, daily reading goals, streaks, gamification; syncs when signed in.\n\n'
        'LANGUAGES: English, Spanish, French, Arabic, Turkish, Chinese (dictionary limited for Chinese).';

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
    String outputLanguage = 'English',
  }) async {
    final text = _prepareDocumentText(documentText);
    final seed = Random().nextInt(99999);
    final safeCount = count.clamp(3, 30);
    final lang = _outputLanguageInstruction(outputLanguage);

    final system =
        'You are a study flashcard generator. $lang '
        'Output ONLY a JSON array with exactly $safeCount objects. '
        'No markdown, no code fences, no explanation. '
        'Each object must have string fields "question" and "answer" with real content — never "-" or empty strings. '
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

  /// Answers questions about a specific document or note transcript.
  static Future<String> askAboutDocument({
    required String documentText,
    required String userMessage,
    String? documentTitle,
    List<Map<String, String>>? conversationHistory,
    String outputLanguage = 'English',
  }) {
    final text = _prepareDocumentText(documentText);
    final title = (documentTitle?.trim().isNotEmpty ?? false)
        ? documentTitle!.trim()
        : 'Document';
    const docMax = 10000;
    final docBody = text.length > docMax
        ? '${text.substring(0, docMax)}\n\n[Document truncated for length...]'
        : text;

    final history = StringBuffer();
    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      history.writeln('\nPrevious conversation:');
      for (final msg in conversationHistory) {
        final role = msg['role'] == 'user' ? 'User' : 'Assistant';
        final content = (msg['content'] ?? '').trim();
        if (content.isNotEmpty) {
          history.writeln('$role: $content');
        }
      }
      history.writeln();
    }

    final lang = _outputLanguageInstruction(outputLanguage);
    final system =
        'You are Vox Study Buddy, a helpful reading assistant. $lang '
        'Answer questions using ONLY the provided document text. '
        'If the user writes in another language, reply in that language. '
        'If the answer is not in the document, say so clearly and briefly. '
        'Keep answers concise, friendly, and accurate. Plain text only.';

    final prompt =
        'Document title: $title\n\n'
        'Document text:\n"""$docBody"""\n'
        '${history.toString()}'
        'User question:\n"""${userMessage.trim()}"""';

    return _callLlm(system, prompt, temperature: 0.35, maxTokens: 2048);
  }
}

class Flashcard {
  final String question;
  final String answer;
  const Flashcard({required this.question, required this.answer});
}
