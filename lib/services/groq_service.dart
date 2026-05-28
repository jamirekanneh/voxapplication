import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/secrets.dart';

class GroqService {
  static const String _endpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';

  static Future<String> transcribeAudio(String audioUrl) async {
    final apiKey = kGroqApiKey;
    if (apiKey.isEmpty) {
      throw Exception(
        'Groq API key is missing. Add GROQ_API_KEY to assets/project.env and restart the app.',
      );
    }

    late List<int> audioBytes;
    try {
      final download = await http
          .get(Uri.parse(audioUrl))
          .timeout(const Duration(seconds: 60));
      if (download.statusCode != 200) {
        throw Exception(
          'Could not download audio for transcription (${download.statusCode}).',
        );
      }
      audioBytes = download.bodyBytes;
      if (audioBytes.isEmpty) {
        throw Exception('Downloaded audio file is empty.');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Could not download audio. Check internet and try again.');
    }

    late http.Response response;
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_endpoint))
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..fields['model'] = 'whisper-large-v3'
        ..fields['response_format'] = 'json'
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            audioBytes,
            filename: 'recording.m4a',
          ),
        );

      final streamed = await request.send().timeout(const Duration(seconds: 90));
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      throw Exception(
        'Could not reach Groq. Check internet connection and try again.',
      );
    }

    if (response.statusCode != 200) {
      String message = 'Groq transcription failed (${response.statusCode}).';
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final err = decoded['error'];
        if (err is Map<String, dynamic>) {
          final code = (err['code'] ?? '').toString();
          final type = (err['type'] ?? '').toString();
          final msg = (err['message'] ?? '').toString();
          if (code == 'invalid_api_key' || type == 'invalid_request_error') {
            message =
                'Groq API key is invalid. Update GROQ_API_KEY in assets/project.env.';
          } else if (response.statusCode == 429) {
            message = 'Groq rate limit reached. Please try again shortly.';
          } else if (msg.isNotEmpty) {
            message = 'Groq transcription failed: $msg';
          }
        }
      } catch (_) {}
      throw Exception(message);
    }

    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic>) {
      return (data['text'] as String? ?? '').trim();
    }
    return '';
  }

  static bool isTranscriptPending(String? content) {
    if (content == null || content.trim().isEmpty) return true;
    final c = content.trim().toLowerCase();
    return c.contains('transcript pending') || c == '[audio note]';
  }
}
