import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/secrets.dart';

class GroqService {
  static const String _endpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';

  /// Transcribe from a Firebase/download URL (fallback when local file is gone).
  static Future<String> transcribeAudio(
    String audioUrl, {
    Duration? expectedDuration,
  }) async {
    final download = await http
        .get(Uri.parse(audioUrl))
        .timeout(const Duration(seconds: 60));
    if (download.statusCode != 200) {
      throw Exception(
        'Could not download audio for transcription (${download.statusCode}).',
      );
    }
    final bytes = download.bodyBytes;
    if (bytes.isEmpty) {
      throw Exception('Downloaded audio file is empty.');
    }
    if (expectedDuration != null && expectedDuration.inSeconds >= 3) {
      final minBytes = expectedDuration.inSeconds * 1200;
      if (bytes.length < minBytes) {
        throw Exception(
          'Uploaded audio is too small for a ${expectedDuration.inSeconds}s '
          'recording. Re-record with microphone permission enabled.',
        );
      }
    }
    return _transcribeBytes(bytes, filename: 'recording.m4a');
  }

  /// Wait until the recorder has flushed the file to disk.
  static Future<void> ensureLocalAudioReady(String localPath) =>
      _waitForFileReady(File(localPath));

  /// Preferred path: transcribe directly from the on-device recording file.
  static Future<String> transcribeLocalFile(
    String localPath, {
    Duration? expectedDuration,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('Audio file not found on device.');
    }
    await _waitForFileReady(file);
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Audio file is empty.');
    }
    if (expectedDuration != null && expectedDuration.inSeconds >= 3) {
      final minBytes = expectedDuration.inSeconds * 1200;
      if (bytes.length < minBytes) {
        throw Exception(
          'Recording looks empty (${bytes.length} bytes for '
          '${expectedDuration.inSeconds}s). The microphone may not have '
          'captured audio — enable mic permission and close assistant voice '
          'before recording.',
        );
      }
    }
    final name = localPath.split(Platform.pathSeparator).last;
    return _transcribeBytes(bytes, filename: name.endsWith('.') ? 'recording.m4a' : name);
  }

  static Future<void> _waitForFileReady(File file) async {
    const attempts = 25;
    const delay = Duration(milliseconds: 120);
    var lastSize = -1;
    for (var i = 0; i < attempts; i++) {
      if (!await file.exists()) {
        await Future<void>.delayed(delay);
        continue;
      }
      final size = await file.length();
      if (size >= 1024 && size == lastSize) return;
      lastSize = size;
      await Future<void>.delayed(delay);
    }
    if (await file.exists() && await file.length() >= 512) return;
    throw Exception(
      'Recording file is not ready yet. Wait a moment and try again.',
    );
  }

  static Future<String> _transcribeBytes(
    List<int> audioBytes, {
    required String filename,
  }) async {
    final apiKey = kGroqApiKey;
    if (apiKey.isEmpty) {
      throw Exception(
        'Groq API key is missing. Add GROQ_API_KEY to assets/project.env and restart the app.',
      );
    }
    if (audioBytes.length < 512) {
      throw Exception(
        'Audio file is too small (${audioBytes.length} bytes). '
        'The recording may not have finished saving.',
      );
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
            filename: filename,
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
