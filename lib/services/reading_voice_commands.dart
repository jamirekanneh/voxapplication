import 'package:flutter/foundation.dart';

import '../tts_service.dart';

/// Result of parsing/executing a hands-free reading command while TTS is active.
class ReadingVoiceResult {
  final bool handled;
  final String feedback;
  final bool closeReader;
  final String? dictionaryQuery;

  const ReadingVoiceResult({
    required this.handled,
    this.feedback = '',
    this.closeReader = false,
    this.dictionaryQuery,
  });

  static const none = ReadingVoiceResult(handled: false);
}

/// Shared voice commands for document read-aloud (Home library reader + mini player).
class ReadingVoiceCommands {
  ReadingVoiceCommands._();

  static String _normalize(String spoken) {
    return spoken
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _has(String words, List<String> keys) =>
      keys.any((k) => words.contains(k));

  /// Extract word for "define X", "what does X mean", "stop and define X".
  static String? _extractDefineQuery(String words) {
    final patterns = [
      RegExp(r'stop\s+and\s+define\s+(.+)'),
      RegExp(r'define\s+(?:the\s+word\s+)?(.+)'),
      RegExp(r'what\s+does\s+(.+?)\s+mean'),
      RegExp(r'meaning\s+of\s+(.+)'),
      RegExp(r'look\s+up\s+(.+)'),
      RegExp(r'what\s+is\s+(.+)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(words);
      if (m != null) {
        var q = m.group(1)?.trim() ?? '';
        q = q.replaceAll(RegExp(r'\b(please|now|word)\b'), '').trim();
        if (q.length >= 2 && q.length <= 60) return q;
      }
    }
    return null;
  }

  /// Returns true if [spoken] looks like a reading control phrase.
  static bool looksLikeReadingCommand(String spoken) {
    final w = _normalize(spoken);
    if (w.isEmpty) return false;
    if (_extractDefineQuery(w) != null) return true;
    return _has(w, [
      'pause',
      'resume',
      'continue',
      'play',
      'stop',
      'close',
      'exit',
      'quit',
      'forward',
      'skip',
      'back',
      'rewind',
      'faster',
      'slower',
      'speed up',
      'slow down',
      'restart',
      'beginning',
      'highlight',
      'mark',
      'define',
      'meaning',
    ]);
  }

  /// Execute reading controls on [tts]. Does not navigate — caller handles [closeReader] / dictionary.
  static Future<ReadingVoiceResult> execute({
    required String spoken,
    required TtsService tts,
    required String locale,
  }) async {
    final words = _normalize(spoken);
    if (words.isEmpty) return ReadingVoiceResult.none;

    // ── Define / dictionary (pause first) ──
    final defineQuery = _extractDefineQuery(words);
    if (defineQuery != null) {
      if (tts.isPlaying) await tts.togglePause(locale);
      return ReadingVoiceResult(
        handled: true,
        feedback: '📖 Lookup: $defineQuery',
        dictionaryQuery: defineQuery,
      );
    }

    // ── Close document ──
    if (_has(words, [
      'close doc',
      'close document',
      'close the document',
      'close reader',
      'close file',
      'exit reader',
      'quit reader',
      'exit document',
    ]) ||
        words == 'close' ||
        words == 'exit' ||
        words == 'quit') {
      await tts.stop();
      return const ReadingVoiceResult(
        handled: true,
        feedback: '🛑 Closed',
        closeReader: true,
      );
    }

    // ── Pause ──
    if (_has(words, [
      'pause',
      'pause reading',
      'stop reading',
      'hold on',
      'wait',
      'hold',
    ]) ||
        words == 'stop') {
      if (tts.isPlaying) await tts.togglePause(locale);
      return const ReadingVoiceResult(
        handled: true,
        feedback: '⏸ Paused',
      );
    }

    // ── Resume ──
    if (_has(words, [
      'play',
      'resume',
      'continue',
      'continue reading',
      'keep reading',
      'start reading',
      'read',
    ])) {
      if (!tts.isPlaying && tts.content != null) {
        await tts.togglePause(locale);
      }
      return const ReadingVoiceResult(
        handled: true,
        feedback: '▶ Playing',
      );
    }

    // ── Seek / speed ──
    if (_has(words, ['forward', 'skip', 'skip ahead', 'next'])) {
      await tts.seekForward(10, locale);
      return const ReadingVoiceResult(
        handled: true,
        feedback: '⏭ +10 seconds',
      );
    }
    if (_has(words, ['back', 'backward', 'rewind', 'go back', 'previous'])) {
      await tts.seekBackward(10, locale);
      return const ReadingVoiceResult(
        handled: true,
        feedback: '⏮ −10 seconds',
      );
    }
    if (_has(words, ['faster', 'speed up', 'increase speed', 'go faster'])) {
      await tts.setRate((tts.speechRate + 0.2).clamp(0.1, 2.0), locale);
      return const ReadingVoiceResult(
        handled: true,
        feedback: '⚡ Faster',
      );
    }
    if (_has(words, ['slower', 'slow down', 'decrease speed', 'go slower'])) {
      await tts.setRate((tts.speechRate - 0.2).clamp(0.1, 2.0), locale);
      return const ReadingVoiceResult(
        handled: true,
        feedback: '🐢 Slower',
      );
    }
    if (_has(words, ['restart', 'start over', 'from the beginning', 'beginning'])) {
      await tts.restart(locale);
      return const ReadingVoiceResult(
        handled: true,
        feedback: '🔄 Restarted',
      );
    }

    // ── Stop playback (stay on reader) ──
    if (_has(words, ['stop playback', 'end reading', 'stop read aloud'])) {
      await tts.stop();
      return const ReadingVoiceResult(
        handled: true,
        feedback: '🛑 Stopped',
      );
    }

    return ReadingVoiceResult.none;
  }

  /// When document TTS is active, try reading command before global navigation.
  static Future<ReadingVoiceResult> tryDuringPlayback({
    required String spoken,
    required TtsService tts,
    required String locale,
  }) async {
    if (tts.content == null || !tts.isVisible) {
      return ReadingVoiceResult.none;
    }
    if (!looksLikeReadingCommand(spoken)) {
      return ReadingVoiceResult.none;
    }
    final result = await execute(spoken: spoken, tts: tts, locale: locale);
    debugPrint('ReadingVoiceCommands: "$spoken" -> handled=${result.handled}');
    return result;
  }
}
