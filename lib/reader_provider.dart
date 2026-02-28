import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class ReaderProvider extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();

  String? title;
  String? content;
  bool isPlaying = false;
  bool isVisible = false;
  double speechRate = 1.0;
  double progress = 0.0;
  int wordStart = 0;
  int wordEnd = 0;

  ReaderProvider() {
    _tts.setCompletionHandler(() {
      isPlaying = false;
      progress = 1.0;
      notifyListeners();
    });
    _tts.setProgressHandler((text, start, end, word) {
      final total = text.length;
      if (total > 0) {
        progress = end / total;
        wordStart = start;
        wordEnd = end;
      }
      notifyListeners();
    });
  }

  Future<void> play(String t, String c, String locale) async {
    await _tts.stop();
    title = t;
    content = c;
    isPlaying = true;
    isVisible = true;
    progress = 0.0;
    wordStart = 0;
    wordEnd = 0;
    await _tts.setLanguage(locale);
    await _tts.setSpeechRate(speechRate);
    await _tts.setPitch(1.0);
    notifyListeners();
    await _tts.speak(c);
  }

  Future<void> togglePause(String locale) async {
    if (isPlaying) {
      await _tts.pause();
      isPlaying = false;
    } else {
      if (content != null) {
        await _tts.setLanguage(locale);
        await _tts.speak(content!);
        isPlaying = true;
      }
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _tts.stop();
    isPlaying = false;
    isVisible = false;
    title = null;
    content = null;
    progress = 0.0;
    wordStart = 0;
    wordEnd = 0;
    notifyListeners();
  }

  // FIX: setRate doesn't restart from beginning — just updates rate
  // On Android we must stop/speak to apply rate, but we keep this minimal
  Future<void> setRate(double rate, String locale) async {
    speechRate = rate.clamp(0.1, 2.0);
    await _tts.setSpeechRate(speechRate);
    if (isPlaying && content != null) {
      await _tts.stop();
      await _tts.setLanguage(locale);
      await _tts.speak(content!);
    }
    notifyListeners();
  }

  Future<void> restart(String locale) async {
    if (content != null) {
      await play(title ?? '', content!, locale);
    }
  }
}
