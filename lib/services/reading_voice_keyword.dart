import 'reading_playback_state.dart';
import 'reading_voice_keywords_i18n.dart';

/// Core voice triggers for read-aloud (keyword spotter — not full dictation).
enum ReadingVoiceKeyword {
  pause,
  stop,
  play,
  forward,
  backward,
  highlight,
}

/// Local keyword spotter: scans only the **tail** of STT output so accumulated
/// TTS echo does not drown out short commands like "pause" or "forward".
class ReadingVoiceKeywordSpotter {
  ReadingVoiceKeywordSpotter._();

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
    String commandLanguage = 'English',
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
    if (_isStop(tail, commandLanguage)) return ReadingVoiceKeyword.stop;
    if (_isPause(tail, commandLanguage)) return ReadingVoiceKeyword.pause;

    if (state == ReadingPlaybackState.playing) {
      if (_isHighlight(tail, commandLanguage)) {
        return ReadingVoiceKeyword.highlight;
      }
      if (_isForward(tail, commandLanguage)) return ReadingVoiceKeyword.forward;
      if (_isBackward(tail, commandLanguage)) {
        return ReadingVoiceKeyword.backward;
      }
      return null;
    }

    if (state == ReadingPlaybackState.paused) {
      if (_isPlay(tail, commandLanguage)) return ReadingVoiceKeyword.play;
      if (_isHighlight(tail, commandLanguage)) {
        return ReadingVoiceKeyword.highlight;
      }
      if (_isForward(tail, commandLanguage)) return ReadingVoiceKeyword.forward;
      if (_isBackward(tail, commandLanguage)) {
        return ReadingVoiceKeyword.backward;
      }
    }

    return null;
  }

  /// Seek-only match — bypasses TTS echo filter for fast partial STT.
  static ReadingVoiceKeyword? spotSeekOnly(
    String spoken, {
    String commandLanguage = 'English',
  }) {
    final tail = tailWords(spoken, maxWords: 4);
    if (tail.isEmpty) return null;
    if (_isForward(tail, commandLanguage)) return ReadingVoiceKeyword.forward;
    if (_isBackward(tail, commandLanguage)) return ReadingVoiceKeyword.backward;
    return null;
  }

  /// Highlight-only match — bypasses TTS echo filter for fast partial STT.
  static ReadingVoiceKeyword? spotHighlightOnly(
    String spoken, {
    String commandLanguage = 'English',
  }) {
    final tail = tailWords(spoken, maxWords: 4);
    if (tail.isEmpty) return null;
    if (_isHighlight(tail, commandLanguage)) {
      return ReadingVoiceKeyword.highlight;
    }
    return null;
  }

  static bool _isStop(String tail, String commandLanguage) {
    if (_containsWord(tail, ReadingVoiceKeywordsI18n.stopWords(commandLanguage))) {
      return true;
    }
    return _matchesPhrase(tail, ReadingVoiceKeywordsI18n.stopPhrases(commandLanguage));
  }

  static bool _isPause(String tail, String commandLanguage) {
    if (_containsWord(tail, ReadingVoiceKeywordsI18n.pauseWords(commandLanguage))) {
      return true;
    }
    return _matchesPhrase(tail, ReadingVoiceKeywordsI18n.pausePhrases(commandLanguage));
  }

  static bool _isPlay(String tail, String commandLanguage) {
    if (_containsWord(tail, ReadingVoiceKeywordsI18n.playWords(commandLanguage))) {
      return true;
    }
    return _matchesPhrase(tail, ReadingVoiceKeywordsI18n.playPhrases(commandLanguage));
  }

  static bool _isForward(String tail, String commandLanguage) {
    if (_containsWord(tail, ReadingVoiceKeywordsI18n.forwardWords(commandLanguage))) {
      return true;
    }
    return _matchesPhrase(tail, ReadingVoiceKeywordsI18n.forwardPhrases(commandLanguage));
  }

  static bool _isBackward(String tail, String commandLanguage) {
    if (_containsWord(tail, ReadingVoiceKeywordsI18n.backwardWords(commandLanguage))) {
      return true;
    }
    return _matchesPhrase(tail, ReadingVoiceKeywordsI18n.backwardPhrases(commandLanguage));
  }

  static bool _isHighlight(String tail, String commandLanguage) {
    if (_containsWord(tail, ReadingVoiceKeywordsI18n.highlightWords(commandLanguage))) {
      return true;
    }
    return _matchesPhrase(
      tail,
      ReadingVoiceKeywordsI18n.highlightPhrases(commandLanguage),
    );
  }

  static String feedbackFor(
    ReadingVoiceKeyword keyword, {
    String commandLanguage = 'English',
  }) =>
      ReadingVoiceKeywordsI18n.feedback(keyword, commandLanguage);

  static bool isInterrupt(ReadingVoiceKeyword keyword) =>
      interruptKeywords.contains(keyword);
}
