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

/// Shared voice commands for document read-aloud (upload reader + notes + mini player).
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

  static bool _isExact(String words, List<String> keys) =>
      keys.any((k) => words == k);

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

  static const _playbackKeys = [
    'pause',
    'resume',
    'continue',
    'play',
    'stop',
    'forward',
    'go forward',
    'go back',
    'skip',
    'back',
    'rewind',
    'backward',
    'faster',
    'slower',
    'restart',
    'highlight',
    'define',
    'close',
    'exit',
  ];

  /// True if [spoken] looks like a read-aloud control phrase while audio is playing.
  static bool looksLikeReadingCommand(String spoken) {
    final w = _normalize(spoken);
    if (w.isEmpty) return false;
    if (_extractDefineQuery(w) != null) return true;
    return _has(w, _playbackKeys) ||
        _has(w, [
          'pause reading',
          'stop reading',
          'stop playback',
          'end reading',
          'continue reading',
          'keep reading',
          'start reading',
          'skip ahead',
          'speed up',
          'slow down',
          'close doc',
          'close document',
          'close reader',
          'mark',
          'meaning',
          'quit',
        ]);
  }

  /// Commands allowed while read-aloud is paused (resume / stop / seek / define).
  static bool looksLikePausedReadingCommand(String spoken) {
    final w = _normalize(spoken);
    if (w.isEmpty) return false;
    if (_extractDefineQuery(w) != null) return true;
    if (_has(w, [
      'play',
      'resume',
      'continue',
      'keep reading',
      'start reading',
      'read',
      'forward',
      'go forward',
      'back',
      'go back',
      'rewind',
      'skip',
      'backward',
      'pause',
    ])) {
      return true;
    }
    return _has(w, [
      'stop',
      'stop playback',
      'stop reading',
      'end reading',
      'close',
      'exit',
      'quit',
      'close doc',
      'close document',
      'close reader',
    ]);
  }

  /// Interrupt keywords — match aggressively on partial STT while TTS is playing.
  static bool looksLikePauseInterrupt(String spoken) {
    final w = _normalize(spoken);
    if (w.isEmpty) return false;
    if (_isExact(w, ['pause', 'paws', 'halt', 'wait', 'hold'])) return true;
    if (_has(w, ['pause reading', 'hold on', 'hold up'])) {
      return w.split(' ').length <= 4;
    }
    final parts = w.split(' ');
    if (parts.length <= 3 &&
        parts.any((p) => ['pause', 'paws', 'wait', 'hold', 'halt'].contains(p))) {
      return true;
    }
    return false;
  }

  /// Stop while TTS is playing — strict to avoid false triggers from document text.
  static bool looksLikeStopInterrupt(String spoken) {
    final w = _normalize(spoken);
    if (w.isEmpty) return false;
    if (_isExact(w, ['stop'])) return true;
    return _has(w, ['stop reading', 'stop playback']) && w.split(' ').length <= 4;
  }

  static bool looksLikeResumeCommand(String spoken) {
    final w = _normalize(spoken);
    if (w.isEmpty) return false;
    return _has(w, [
          'play',
          'resume',
          'continue',
          'continue reading',
          'keep reading',
          'start reading',
          'read on',
        ]) ||
        _isExact(w, ['play', 'resume', 'continue', 'read']);
  }

  static bool looksLikeSeekCommand(String spoken) {
    final w = _normalize(spoken);
    if (w.isEmpty) return false;
    return _has(w, [
      'forward',
      'go forward',
      'skip',
      'skip ahead',
      'back',
      'go back',
      'backward',
      'rewind',
    ]);
  }

  /// True when executing this phrase will start TTS playback again.
  static bool commandStartsPlayback(String spoken) {
    return looksLikeResumeCommand(spoken) || looksLikeSeekCommand(spoken);
  }

  /// Accept partial STT while TTS is playing (short phrases only).
  static bool acceptPartialResult(String spoken) {
    const keys = [
      'pause',
      'stop',
      'play',
      'resume',
      'continue',
      'forward',
      'back',
      'skip',
      'rewind',
      'go',
      'faster',
      'slower',
      'define',
      'close',
      'exit',
    ];
    final w = spoken.toLowerCase().trim();
    if (w.isEmpty) return false;
    if (w.split(' ').length > 4) return false;
    return keys.any((k) => w.contains(k));
  }

  /// Execute reading controls on [tts]. Does not navigate — caller handles [closeReader] / dictionary.
  static Future<ReadingVoiceResult> execute({
    required String spoken,
    required TtsService tts,
    required String locale,
  }) async {
    final words = _normalize(spoken);
    if (words.isEmpty || !tts.isReadingSession) return ReadingVoiceResult.none;

    // ── Define / dictionary (pause first) ──
    final defineQuery = _extractDefineQuery(words);
    if (defineQuery != null) {
      if (tts.isPlaying) await tts.pauseReading(locale);
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
        _isExact(words, ['close', 'exit', 'quit'])) {
      await tts.stop();
      return const ReadingVoiceResult(
        handled: true,
        feedback: '🛑 Closed',
        closeReader: true,
      );
    }

    // ── Stop (end read-aloud, keep mini player closed) ──
    if (_has(words, [
          'stop playback',
          'end reading',
          'stop read aloud',
          'stop reading',
        ]) ||
        _isExact(words, ['stop'])) {
      await tts.stop();
      return const ReadingVoiceResult(
        handled: true,
        feedback: '🛑 Stopped',
      );
    }

    // ── Pause ──
    if (_has(words, [
          'pause',
          'pause reading',
          'hold on',
          'wait',
          'hold',
        ]) ||
        _isExact(words, ['pause'])) {
      if (tts.isPlaying || !tts.userPaused) {
        await tts.pauseReading(locale);
      }
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
          'read on',
        ]) ||
        _isExact(words, ['play', 'resume', 'continue', 'read'])) {
      if (tts.userPaused && !tts.isPlaying) {
        await tts.resumeReading(locale);
      }
      return const ReadingVoiceResult(
        handled: true,
        feedback: '▶ Playing',
      );
    }

    // ── Seek forward ──
    if (_has(words, [
      'forward',
      'go forward',
      'skip',
      'skip ahead',
      'next',
      'forward 10',
      'skip 10',
      'ten seconds',
    ])) {
      await tts.seekForward(10, locale);
      return const ReadingVoiceResult(
        handled: true,
        feedback: '⏭ +10 seconds',
      );
    }

    // ── Seek backward ──
    if (_has(words, [
      'back',
      'go back',
      'backward',
      'rewind',
      'previous',
      'back 10',
      'go back 10',
      'ten seconds back',
    ])) {
      await tts.seekBackward(10, locale);
      return const ReadingVoiceResult(
        handled: true,
        feedback: '⏮ −10 seconds',
      );
    }

    // ── Speed ──
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

    if (_has(words, ['highlight', 'mark', 'highlight that', 'mark text'])) {
      if (onHighlightSentence != null) {
        onHighlightSentence!(tts);
        return const ReadingVoiceResult(
          handled: true,
          feedback: '🖍️ Sentence highlighted',
        );
      }
    }

    return ReadingVoiceResult.none;
  }

  /// Reader-only: pin the current sentence when user says "highlight".
  static void Function(TtsService tts)? onHighlightSentence;

  /// When document TTS is active, try reading command before global navigation.
  static Future<ReadingVoiceResult> tryDuringPlayback({
    required String spoken,
    required TtsService tts,
    required String locale,
  }) async {
    if (!tts.isReadingSession) {
      return ReadingVoiceResult.none;
    }
    if (!tts.isPlaying && !tts.userPaused) {
      return ReadingVoiceResult.none;
    }
    final looksLike = tts.isPlaying
        ? looksLikeReadingCommand(spoken)
        : looksLikePausedReadingCommand(spoken);
    if (!looksLike) {
      return ReadingVoiceResult.none;
    }
    final result = await execute(spoken: spoken, tts: tts, locale: locale);
    debugPrint('ReadingVoiceCommands: "$spoken" -> handled=${result.handled}');
    return result;
  }
}
