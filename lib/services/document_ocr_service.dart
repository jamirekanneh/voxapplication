import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'document_language_service.dart';

/// Runs on-device OCR with script selection for the six supported languages.
class DocumentOcrService {
  DocumentOcrService._();

  static Future<String> recognizeFromFilePath(
    String path, {
    required String preferredLanguage,
    bool forScan = false,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      debugPrint('DocumentOcrService: image missing at $path');
      return '';
    }
    if (await file.length() == 0) {
      debugPrint('DocumentOcrService: empty image at $path');
      return '';
    }

    final scripts = forScan
        ? DocumentLanguageService.ocrScriptsForScan(preferredLanguage)
        : DocumentLanguageService.ocrScriptsToTry(preferredLanguage);

    var best = '';
    var bestScore = 0;

    for (final script in scripts) {
      TextRecognizer? recognizer;
      try {
        recognizer = TextRecognizer(script: script);
        final result = await recognizer.processImage(
          InputImage.fromFilePath(file.absolute.path),
        );
        final text = result.text.trim();
        final score = _scoreText(text, preferredLanguage);
        if (score > bestScore) {
          bestScore = score;
          best = text;
        }
      } catch (e, st) {
        debugPrint('DocumentOcrService ($script): $e\n$st');
      } finally {
        await recognizer?.close();
      }
    }

    return best;
  }

  static int _scoreText(String text, String preferredLanguage) {
    if (text.isEmpty) return 0;
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    var score = compact.length;
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(text).length;
    final digits = RegExp(r'\d').allMatches(text).length;
    score += letters + (digits ~/ 2);

    final detected = DocumentLanguageService.detectLanguageName(
      text,
      fallback: preferredLanguage,
    );
    if (detected == preferredLanguage) score += 40;

    // Prefer results with real words over OCR noise.
    final words = text.split(RegExp(r'\s+')).where((w) => w.length >= 2).length;
    score += words * 3;

    return score;
  }

  static Future<void> deleteTempFile(String? path) async {
    if (path == null || path.isEmpty) return;
    if (path.startsWith('content://')) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}
