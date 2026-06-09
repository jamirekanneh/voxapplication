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

    final scripts = DocumentLanguageService.ocrScriptsToTry(preferredLanguage);
    var best = '';

    for (final script in scripts) {
      TextRecognizer? recognizer;
      try {
        recognizer = TextRecognizer(script: script);
        final result = await recognizer.processImage(
          InputImage.fromFilePath(file.absolute.path),
        );
        final text = result.text.trim();
        if (text.length > best.length) best = text;
      } catch (e, st) {
        debugPrint('DocumentOcrService ($script): $e\n$st');
      } finally {
        await recognizer?.close();
      }
    }

    return best;
  }

  static Future<void> deleteTempFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}
