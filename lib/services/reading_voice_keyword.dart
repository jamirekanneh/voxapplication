import 'reading_playback_state.dart';

/// Core voice triggers for read-aloud (keyword spotter — not full dictation).
enum ReadingVoiceKeyword {
  pause,
  stop,
  play,
  forward,
  backward,
}

/// Local keyword spotter: scans only the **tail** of STT output so accumulated
/// TTS echo does not drown out short commands like "pause" or "forward".
class ReadingVoiceKeywordSpotter {
  ReadingVoiceKeywordSpotter._();

  static const _pauseWords = {'pause', 'paws', 'halt', 'wait', 'hold'};
  static const _stopWords = {'stop', 'end', 'quit'};
  static const _playWords = {
    'play',
    'resume',
    'continue',
    'unpause',
    'start',
    'read',
  };
  static const _forwardWords = {'forward', 'skip', 'next'};
  static const _backwardWords = {'back', 'backward', 'rewind', 'previous'};

  /// Interrupt-class commands — highest priority while [PLAYING].
  static const interruptKeywords = {
    ReadingVoiceKeyword.stop,
    ReadingVoiceKeyword.pause,
  };

  static String normalize(String spoken) {
    return spoken
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Keep only the last [maxWords] — STT accumulates the whole session.
  static String tailWords(String spoken, {int maxWords = 4}) {
    final parts = normalize(spoken).split(' ').where((p) => p.isNotEmpty);
    final list = parts.toList();
    if (list.length <= maxWords) return list.join(' ');
    return list.sublist(list.length - maxWords).join(' ');
  }

  /// Reject long transcripts that are almost certainly TTS bleed-through.
  static bool isLikelyTtsEcho(String fullTranscript, String recentTtsSnippet) {
    final full = normalize(fullTranscript);
    if (full.split(' ').length < 6) return false;
    if (recentTtsSnippet.isEmpty) return false;
    final snippet = normalize(recentTtsSnippet);
    if (snippet.length < 12) return false;
    // Long partial that overlaps recently spoken TTS text → echo.
    final tail = tailWords(full, maxWords: 6);
    return snippet.contains(tail) && tail.split(' ').length >= 3;
  }

  static bool _containsWord(String haystack, Set<String> words) {
    final parts = haystack.split(' ');
    return parts.any(words.contains);
  }

  static bool _matchesPhrase(String haystack, List<String> phrases) {
    return phrases.any((p) => haystack == p || haystack.endsWith(' $p') || haystack.startsWith('$p '));
  }

  /// Spot a command from the tail of [spoken] given current playback state.
  static ReadingVoiceKeyword? spot({
    required String spoken,
    required ReadingPlaybackState state,
    String recentTtsSnippet = '',
    bool ignoreTtsEcho = false,
  }) {
    // Echo filter only applies while audio plays through the phone speaker.
    if (!ignoreTtsEcho &&
        state == ReadingPlaybackState.playing &&
        isLikelyTtsEcho(spoken, recentTtsSnippet)) {
      return null;
    }

    final tail = tailWords(spoken, maxWords: 4);
    if (tail.isEmpty) return null;

    // ── Interrupt priority (stop before pause) ──
    if (_isStop(tail)) return ReadingVoiceKeyword.stop;
    if (_isPause(tail)) return ReadingVoiceKeyword.pause;

    if (state == ReadingPlaybackState.playing) {
      if (_isForward(tail)) return ReadingVoiceKeyword.forward;
      if (_isBackward(tail)) return ReadingVoiceKeyword.backward;
      return null;
    }

    if (state == ReadingPlaybackState.paused) {
      if (_isPlay(tail)) return ReadingVoiceKeyword.play;
      if (_isForward(tail)) return ReadingVoiceKeyword.forward;
      if (_isBackward(tail)) return ReadingVoiceKeyword.backward;
    }

    return null;
  }

  static bool _isStop(String tail) {
    if (_containsWord(tail, _stopWords)) return true;
    return _matchesPhrase(tail, ['stop reading', 'stop playback', 'end reading']);
  }

  static bool _isPause(String tail) {
    if (_containsWord(tail, _pauseWords)) return true;
    return _matchesPhrase(tail, ['pause reading', 'hold on', 'hold up']);
  }

  static bool _isPlay(String tail) {
    if (_containsWord(tail, _playWords)) return true;
    return _matchesPhrase(tail, [
      'continue reading',
      'keep reading',
      'start reading',
    ]);
  }

  static bool _isForward(String tail) {
    if (_containsWord(tail, _forwardWords)) return true;
    return _matchesPhrase(tail, ['go forward', 'skip ahead']);
  }

  static bool _isBackward(String tail) {
    if (_containsWord(tail, _backwardWords)) return true;
    return _matchesPhrase(tail, ['go back']);
  }

  static String feedbackFor(ReadingVoiceKeyword keyword) {
    switch (keyword) {
      case ReadingVoiceKeyword.pause:
        return '⏸ Paused';
      case ReadingVoiceKeyword.stop:
        return '🛑 Stopped';
      case ReadingVoiceKeyword.play:
        return '▶ Playing';
      case ReadingVoiceKeyword.forward:
        return '⏭ Forward';
      case ReadingVoiceKeyword.backward:
        return '⏮ Back';
    }
  }

  static bool isInterrupt(ReadingVoiceKeyword keyword) =>
      interruptKeywords.contains(keyword);
}
