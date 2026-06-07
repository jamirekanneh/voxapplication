import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'analytics_service.dart';
import 'services/mic_coordinator.dart';
import 'services/read_aloud_ui.dart';
import 'services/headphone_audio_detector.dart';
import 'services/read_aloud_voice_service.dart';
import 'services/reading_audio_session.dart';

class TtsService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();

  List<Map<String, String>> _availableVoices = [];
  Map<String, String>? _selectedVoice;

  bool isPlaying = false;
  bool isVisible = false;
  /// User tapped pause; [content] position is kept for resume.
  bool userPaused = false;
  bool _suppressCompletion = false;
  bool _pendingVoiceControlsTip = false;
  bool _briefSpeaking = false;
  /// When true, [MiniPlayerBar] is hidden (e.g. full-screen reader has its own controls).
  bool suppressGlobalMiniPlayer = false;
  double speechRate = 0.5;

  void setSuppressGlobalMiniPlayer(bool suppress) {
    if (suppressGlobalMiniPlayer == suppress) return;
    suppressGlobalMiniPlayer = suppress;
    notifyListeners();
  }

  /// Global pause/play bar — only for upload or notes document read-aloud.
  bool get showGlobalMiniPlayer => isVisible && !suppressGlobalMiniPlayer;
  double progress = 0.0;

  // Word-level highlight
  int wordStart = 0;
  int wordEnd = 0;

  // Sentence-level highlight
  int sentenceStart = 0;
  int sentenceEnd = 0;

  String? title;
  String? content;

  // Tracks char position so we can seek forward/back
  int _currentCharOffset = 0;
  int _displayCharPos = 0;
  /// Where the current TTS segment begins inside [content] (changes after pause/seek).
  int _segmentBaseOffset = 0;
  int _lastEngineCharPos = 0;
  DateTime _playbackStartedAt = DateTime.now();
  DateTime? _lastEngineProgressAt;
  int _playbackAnchorChar = 0;
  Timer? _highlightTimer;

  /// App slider value that matches ~1× spoken pace on device TTS.
  static const double _baselineSpeechRate = 0.5;
  static const double _fullVolume = 1.0;
  /// Baseline while hands-free mic is active during playback (~85% quieter).
  static const double _handsFreeBaselineVolume = 0.15;
  /// Extra dip when the mic hears speech (~97% quieter).
  static const double _commandDuckVolume = 0.03;

  bool _volumeDucked = false;
  bool _handsFreeVolumeActive = false;
  bool _deepVoiceDuck = false;
  DateTime? _deepDuckUntil;
  Timer? _handsFreeVolumeTimer;
  bool get isVolumeDucked => _volumeDucked;

  double get _targetHandsFreeVolume =>
      _deepVoiceDuck ? _commandDuckVolume : _handsFreeBaselineVolume;
  String _recentTtsSnippet = '';

  /// Android/iOS TTS engines often truncate near 4k chars — chain chunks for long docs.
  static const int _maxSpeakChunkChars = 3800;
  String? _readingLocale;
  int _activeChunkEnd = 0;

  final List<_SentenceSpan> _sentenceSpans = [];
  int _activeSentenceIndex = 0;

  List<Map<String, String>> get availableVoices => _availableVoices;
  Map<String, String>? get selectedVoice => _selectedVoice;

  /// One brief voice-controls hint per [play] session.
  bool consumeVoiceControlsTip() {
    if (!_pendingVoiceControlsTip) return false;
    _pendingVoiceControlsTip = false;
    return true;
  }

  TtsService() {
    _init();
  }

  /// True while a document read-aloud session is open (mini player / reader).
  bool get isReadingSession => isVisible && content != null;

  /// Recently spoken TTS text — used to filter echo from the mic.
  String get recentTtsSnippet => _recentTtsSnippet;

  Future<void> _haltTtsEngine() async {
    _suppressCompletion = true;
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _tts.pause();
    } catch (_) {}
    _suppressCompletion = false;
  }

  Future<void> _safeStop() => _haltTtsEngine();

  Future<void> _init() async {
    // Non-blocking speak so pause/resume UI stays in sync.
    await _tts.awaitSpeakCompletion(false);
    await _configureTtsForSharedAudio();

    _tts.setStartHandler(() {
      if (_briefSpeaking) {
        notifyListeners();
        return;
      }
      if (!isReadingSession || userPaused) return;
      isPlaying = true;
      _reanchorPlayback(_segmentBaseOffset);
      _startHighlightTimer();
      MicCoordinator.instance.setTtsPlaybackActive(true);
      _startHandsFreeVolumeKeepAlive();
      unawaited(_applyReadAloudVolume());
      unawaited(ReadAloudVoiceService.instance.resumeAfterTts());
      notifyListeners();
    });

    _tts.setCompletionHandler(() {
      if (_suppressCompletion) return;
      if (_briefSpeaking) {
        _briefSpeaking = false;
        notifyListeners();
        return;
      }
      if (!isReadingSession) return;

      final total = content!.length;
      if (_activeChunkEnd < total && !userPaused && _readingLocale != null) {
        unawaited(_beginSpeakingAt(_activeChunkEnd, _readingLocale!));
        return;
      }

      isPlaying = false;
      userPaused = false;
      progress = 1.0;
      _stopHighlightTimer();
      if (total > 0) {
        _displayCharPos = total;
        _updateSentenceBounds(total - 1);
      }
      MicCoordinator.instance.setTtsPlaybackActive(false);
      notifyListeners();
    });

    _tts.setPauseHandler(() {
      if (_briefSpeaking) {
        _briefSpeaking = false;
        notifyListeners();
        return;
      }
      if (!isReadingSession) return;
      userPaused = true;
      isPlaying = false;
      _stopHighlightTimer();
      MicCoordinator.instance.setTtsPlaybackActive(false);
      notifyListeners();
    });

    _tts.setCancelHandler(() {
      if (_suppressCompletion) return;
      if (_briefSpeaking) {
        _briefSpeaking = false;
        notifyListeners();
        return;
      }
      if (!isReadingSession) return;
      isPlaying = false;
      _stopHighlightTimer();
      MicCoordinator.instance.setTtsPlaybackActive(false);
      notifyListeners();
    });

    _tts.setProgressHandler((text, start, end, word) {
      final total = content?.length ?? 0;
      if (total == 0 || !isPlaying) return;
      final engineStart = _resolveEngineCharPos(text, start, end, word);
      final engineEnd = (_segmentBaseOffset + end).clamp(engineStart, total);
      _lastEngineProgressAt = DateTime.now();
      _lastEngineCharPos = engineStart;
      _currentCharOffset = engineStart;
      _applyHighlightFromEngine(engineStart, engineEnd);
      _trackRecentTts(text, start, end);
    });

    _tts.setErrorHandler((msg) {
      if (_briefSpeaking) {
        _briefSpeaking = false;
        notifyListeners();
        return;
      }
      isPlaying = false;
      userPaused = false;
      _stopHighlightTimer();
      notifyListeners();
    });

    // Load voices after engine is ready
    await _loadVoices();
  }

  /// Let TTS share the audio session with continuous STT (pause/stop commands).
  Future<void> _configureTtsForSharedAudio() async {
    if (kIsWeb) return;
    try {
      if (Platform.isIOS) {
        await _tts.setSharedInstance(true);
        await _tts.autoStopSharedSession(false);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          ],
          IosTextToSpeechAudioMode.spokenAudio,
        );
      } else if (Platform.isAndroid) {
        await _tts.setAudioAttributesForNavigation();
      }
    } catch (e) {
      debugPrint('TtsService: shared audio config failed: $e');
    }
  }

  /// Document read-aloud — do not take exclusive audio focus (keeps mic alive).
  Future<dynamic> _speakDocument(String text) async {
    if (isReadingSession) {
      await _applyReadAloudVolume();
    } else {
      await ensureFullVolume();
    }
    return _tts.speak(text, focus: false);
  }

  String _speechChunkAt(String fullText, int offset) {
    final start = offset.clamp(0, fullText.length);
    final remaining = fullText.substring(start);
    if (remaining.length <= _maxSpeakChunkChars) return remaining;

    var breakAt = _maxSpeakChunkChars;
    final slice = remaining.substring(0, _maxSpeakChunkChars);
    final paraBreak = slice.lastIndexOf('\n\n');
    if (paraBreak > _maxSpeakChunkChars ~/ 3) {
      breakAt = paraBreak + 2;
    } else {
      for (final sep in ['. ', '! ', '? ', '.\n', '\n']) {
        final idx = slice.lastIndexOf(sep);
        if (idx > _maxSpeakChunkChars ~/ 4) {
          breakAt = idx + sep.length;
          break;
        }
      }
    }
    return remaining.substring(0, breakAt.clamp(1, remaining.length));
  }

  Future<bool> _beginSpeakingAt(int offset, String locale) async {
    if (content == null || content!.isEmpty) return false;
    _readingLocale = locale;
    _segmentBaseOffset = offset;
    _reanchorPlayback(offset);

    final chunk = _speechChunkAt(content!, offset);
    if (chunk.trim().isEmpty) return false;
    _activeChunkEnd = offset + chunk.length;

    if (isReadingSession) {
      final headphones = HeadphoneAudioDetector.instance.isHeadphonesConnected;
      if (headphones) {
        await ensureFullVolume();
      } else {
        await _applyReadAloudVolume();
      }
    } else {
      await ensureFullVolume();
    }

    final result = await _tts.speak(chunk, focus: false);
    return _speakSucceeded(result);
  }

  bool _speakSucceeded(dynamic result) {
    if (result == null) return true;
    if (result is int) return result == 1;
    if (result is bool) return result;
    return true;
  }

  /// Restore full volume after pause / stop (no TTS competing with the mic).
  Future<void> ensureFullVolume() async {
    _stopHandsFreeVolumeKeepAlive();
    _volumeDucked = false;
    _handsFreeVolumeActive = false;
    try {
      await _tts.setVolume(_fullVolume);
    } catch (_) {}
  }

  /// Speechify-style softer level before and during read-aloud with hands-free mic.
  Future<void> _applyReadAloudVolume({bool deepDuck = false}) async {
    if (!isReadingSession) return;
    if (deepDuck) {
      _deepVoiceDuck = true;
      _deepDuckUntil = DateTime.now().add(const Duration(seconds: 2));
    }
    _handsFreeVolumeActive = true;
    _volumeDucked = true;
    try {
      await _tts.setVolume(_targetHandsFreeVolume);
    } catch (_) {}
  }

  /// Called when the hands-free mic opens during playback.
  void onHandsFreeMicActive() {
    if (!isPlaying || !isReadingSession) return;
    if (HeadphoneAudioDetector.instance.isHeadphonesConnected) {
      unawaited(ReadingAudioSession.activateForHeadphoneReadAloud());
      _stopHandsFreeVolumeKeepAlive();
      unawaited(ensureFullVolume());
      return;
    }
    unawaited(ReadingAudioSession.activateForHandsFreeReadAloud());
    _startHandsFreeVolumeKeepAlive();
    unawaited(_applyReadAloudVolume());
  }

  void _startHandsFreeVolumeKeepAlive() {
    if (!isReadingSession) return;
    _handsFreeVolumeTimer?.cancel();
    _handsFreeVolumeTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!isPlaying || !isReadingSession) {
        _stopHandsFreeVolumeKeepAlive(clearDuck: false);
        return;
      }
      if (_deepDuckUntil != null && DateTime.now().isAfter(_deepDuckUntil!)) {
        _deepVoiceDuck = false;
        _deepDuckUntil = null;
      }
      unawaited(_tts.setVolume(_targetHandsFreeVolume));
    });
  }

  void _stopHandsFreeVolumeKeepAlive({bool clearDuck = true}) {
    _handsFreeVolumeTimer?.cancel();
    _handsFreeVolumeTimer = null;
    if (clearDuck) {
      _deepVoiceDuck = false;
      _deepDuckUntil = null;
    }
  }

  /// Deep duck when the mic hears the user over read-aloud audio (phone speaker only).
  void duckVolumeForVoiceCommands() {
    if (!isPlaying || !isReadingSession) return;
    if (HeadphoneAudioDetector.instance.isHeadphonesConnected) return;
    _deepVoiceDuck = true;
    _deepDuckUntil = DateTime.now().add(const Duration(seconds: 3));
    _volumeDucked = true;
    _handsFreeVolumeActive = true;
    if (_handsFreeVolumeTimer == null) {
      _startHandsFreeVolumeKeepAlive();
    }
    unawaited(ReadingAudioSession.activateForHandsFreeReadAloud());
    unawaited(_applyReadAloudVolume(deepDuck: true));
    // Re-apply twice — Android often ignores a single mid-utterance setVolume.
    unawaited(Future<void>.delayed(const Duration(milliseconds: 50), () async {
      if (isPlaying && isReadingSession) {
        try {
          await _tts.setVolume(_commandDuckVolume);
        } catch (_) {}
      }
    }));
  }

  /// Return to hands-free baseline (not full) after a false trigger on phone speaker.
  Future<void> restoreVolumeAfterVoiceCommands() async {
    if (!isPlaying) return;
    if (HeadphoneAudioDetector.instance.isHeadphonesConnected) return;
    _deepVoiceDuck = false;
    _deepDuckUntil = null;
    await _applyReadAloudVolume();
  }

  void _trackRecentTts(String segment, int start, int end) {
    if (segment.isEmpty || end <= start) return;
    final slice = segment.substring(start.clamp(0, segment.length), end.clamp(0, segment.length));
    if (slice.trim().isEmpty) return;
    _recentTtsSnippet = '$_recentTtsSnippet $slice'.trim();
    if (_recentTtsSnippet.length > 160) {
      _recentTtsSnippet = _recentTtsSnippet.substring(_recentTtsSnippet.length - 160);
    }
  }

  void _resetSentenceTracking() {
    _sentenceSpans.clear();
    _activeSentenceIndex = 0;
    _displayCharPos = 0;
  }

  void _parseSentenceSpans(String text) {
    _sentenceSpans.clear();
    if (text.isEmpty) return;

    int start = 0;
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch != '.' && ch != '!' && ch != '?') continue;
      if (i > 0 && i + 1 < text.length && text[i + 1] == '.') continue;

      int end = i + 1;
      while (end < text.length && (text[end] == ' ' || text[end] == '\n')) {
        end++;
      }
      if (end > start) {
        _sentenceSpans.add(_SentenceSpan(start, end));
        start = end;
      }
    }
    if (start < text.length) {
      _sentenceSpans.add(_SentenceSpan(start, text.length));
    }
    if (_sentenceSpans.isEmpty) {
      _sentenceSpans.add(_SentenceSpan(0, text.length));
    }
  }

  /// ~13 chars/sec at speechRate 1.0 — matches seek skip math.
  double _charsPerSecondForRate() => 13.0 * speechRate;

  void _reanchorPlayback(int charPos) {
    final total = content?.length ?? 0;
    final pos = charPos.clamp(0, total);
    _playbackAnchorChar = pos;
    _playbackStartedAt = DateTime.now();
    _lastEngineCharPos = pos;
    _lastEngineProgressAt = DateTime.now();
    _displayCharPos = pos;
  }

  /// Highlight position extrapolated from last anchor at current [speechRate].
  int _extrapolatedHighlightPosition() {
    final total = content?.length ?? 0;
    if (total == 0) return 0;

    if (_lastEngineProgressAt != null) {
      final elapsed =
          DateTime.now().difference(_lastEngineProgressAt!).inMilliseconds /
              1000.0;
      return (_lastEngineCharPos + elapsed * _charsPerSecondForRate())
          .round()
          .clamp(0, total);
    }

    return _timeBasedCharPosition();
  }

  int _timeBasedCharPosition() {
    final total = content?.length ?? 0;
    if (total == 0) return 0;
    final elapsed =
        DateTime.now().difference(_playbackStartedAt).inMilliseconds / 1000.0;
    return (_playbackAnchorChar + elapsed * _charsPerSecondForRate())
        .round()
        .clamp(0, total);
  }

  /// Engine re-anchors; clock extrapolates between events at [speechRate].
  int _resolveEngineCharPos(String segmentText, int start, int end, String word) {
    final text = content;
    if (text == null || text.isEmpty) return 0;

    if (segmentText.isNotEmpty) {
      final from = _segmentBaseOffset.clamp(0, text.length);
      final segmentAt = text.indexOf(segmentText, from);
      if (segmentAt >= 0) _segmentBaseOffset = segmentAt;
    }

    var absoluteStart = (_segmentBaseOffset + start).clamp(0, text.length);

    if (word.isNotEmpty) {
      final searchFrom = (absoluteStart - 20).clamp(0, text.length);
      final wordAt = text.indexOf(word, searchFrom);
      if (wordAt >= 0 && wordAt <= absoluteStart + word.length + 8) {
        absoluteStart = wordAt;
      }
    }

    return absoluteStart;
  }

  void _applyHighlightFromEngine(int engineStart, int engineEnd) {
    final total = content?.length ?? 0;
    if (total == 0) return;
    final display = engineStart.clamp(0, total);
    _displayCharPos = display;
    wordStart = display;
    wordEnd = engineEnd.clamp(display, total);
    progress = display / total;
    _updateSentenceBounds(display);
    notifyListeners();
  }

  void _tickHighlightFromClock() {
    if (!isPlaying || content == null) return;
    final total = content!.length;
    if (total == 0) return;

    final display = _extrapolatedHighlightPosition().clamp(0, total);
    if (display == _displayCharPos) return;
    _displayCharPos = display;
    wordStart = display;
    wordEnd = (display + 1).clamp(0, total);
    progress = display / total;
    _updateSentenceBounds(display);
    notifyListeners();
  }

  void _startHighlightTimer() {
    _highlightTimer?.cancel();
    final rateFactor = speechRate / _baselineSpeechRate;
    final intervalMs = (100 / rateFactor).round().clamp(40, 150);
    _highlightTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) => _tickHighlightFromClock(),
    );
  }

  void _stopHighlightTimer() {
    _highlightTimer?.cancel();
    _highlightTimer = null;
  }

  int _sentenceIndexForCharPos(int charPos) {
    if (_sentenceSpans.isEmpty) return 0;
    for (int i = 0; i < _sentenceSpans.length; i++) {
      if (charPos < _sentenceSpans[i].end) return i;
    }
    return _sentenceSpans.length - 1;
  }

  void _updateSentenceBounds(int charPos) {
    final text = content;
    if (text == null || text.isEmpty) return;
    if (_sentenceSpans.isEmpty) _parseSentenceSpans(text);

    final pos = charPos.clamp(0, text.length);
    var idx = _sentenceIndexForCharPos(pos);

    // Stay on current sentence until playback reaches ~35% of it (avoids early jumps).
    if (_sentenceSpans.length > 1 && idx > _activeSentenceIndex) {
      final current = _sentenceSpans[_activeSentenceIndex];
      final len = (current.end - current.start).clamp(1, text.length);
      final into = pos - current.start;
      if (into < (len * 0.35).round()) {
        idx = _activeSentenceIndex;
      }
    }

    _activeSentenceIndex = idx;
    final active = _sentenceSpans[_activeSentenceIndex];
    sentenceStart = active.start;
    sentenceEnd = active.end;
  }

  Future<void> _loadVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw != null) {
        // Accept ALL voices — no locale filter so user sees everything
        final all = (raw as List)
            .map<Map<String, String>>((v) {
              return {
                'name': v['name']?.toString() ?? '',
                'locale': v['locale']?.toString() ?? '',
              };
            })
            .where((v) => v['name']!.isNotEmpty)
            .toList();

        // Sort: put the app's supported locales first, rest after
        const priority = ['en', 'es', 'fr', 'ar', 'tr', 'zh'];
        all.sort((a, b) {
          final aP = priority.indexWhere(
            (p) => a['locale']!.toLowerCase().startsWith(p),
          );
          final bP = priority.indexWhere(
            (p) => b['locale']!.toLowerCase().startsWith(p),
          );
          final aIdx = aP == -1 ? 999 : aP;
          final bIdx = bP == -1 ? 999 : bP;
          return aIdx.compareTo(bIdx);
        });

        _availableVoices = all;
        if (_availableVoices.isNotEmpty && _selectedVoice == null) {
          _selectedVoice = _availableVoices.first;
        }
      }
    } catch (e) {
      debugPrint('Voice load error: $e');
    }
    notifyListeners();
  }

  Future<void> setVoice(Map<String, String> voice) async {
    _selectedVoice = voice;
    await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!});
    notifyListeners();
    if (isPlaying && content != null) {
      await _safeStop();
      await _beginSpeakingAt(_segmentBaseOffset, _readingLocale ?? 'en-US');
    }
  }

  Future<void> _applyVoiceOrLocale(String locale) async {
    if (_selectedVoice != null) {
      await _tts.setVoice({
        'name': _selectedVoice!['name']!,
        'locale': _selectedVoice!['locale']!,
      });
    } else {
      await _tts.setLanguage(locale);
    }
  }

  /// Short spoken feedback (assistant, navigation, chat) — no mini player.
  Future<void> speakBrief(String text, String locale) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // Don't talk over active document read-aloud.
    if (isPlaying && isVisible) return;

    if (_briefSpeaking) {
      _suppressCompletion = true;
      try {
        await _tts.stop();
      } catch (_) {}
      _suppressCompletion = false;
      _briefSpeaking = false;
    }

    _briefSpeaking = true;
    await _applyVoiceOrLocale(locale);
    await _tts.setSpeechRate(0.55);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.speak(trimmed);
  }

  Future<void> play(String t, String c, String locale) async {
    AnalyticsService.instance.recordTtsUsage();
    await _safeStop();
    title = t;
    content = c;
    userPaused = false;
    isVisible = true;
    isPlaying = false;
    _pendingVoiceControlsTip = true;
    progress = 0.0;
    wordStart = 0;
    wordEnd = 0;
    sentenceStart = 0;
    sentenceEnd = 0;
    _currentCharOffset = 0;
    _segmentBaseOffset = 0;
    _lastEngineCharPos = 0;
    _recentTtsSnippet = '';
    _activeChunkEnd = 0;
    _readingLocale = locale;
    _resetSentenceTracking();
    _parseSentenceSpans(c);
    _reanchorPlayback(0);
    if (_sentenceSpans.isNotEmpty) {
      sentenceStart = _sentenceSpans.first.start;
      sentenceEnd = _sentenceSpans.first.end;
    }

    notifyListeners();

    await HeadphoneAudioDetector.instance.refresh();
    final headphones = HeadphoneAudioDetector.instance.isHeadphonesConnected;

    await ReadingAudioSession.deactivate();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (headphones) {
      await ReadingAudioSession.activateForHeadphoneReadAloud();
    } else {
      await ReadingAudioSession.activateForHandsFreeReadAloud();
    }
    await _configureTtsForSharedAudio();
    await MicCoordinator.instance.prepareForTtsPlayback(stopReadingVoice: true);
    await _applyVoiceOrLocale(locale);
    await _tts.setSpeechRate(speechRate);
    await _tts.setPitch(1.05); // slight pitch boost for more natural tone
    if (headphones) {
      await ensureFullVolume();
    } else {
      await _applyReadAloudVolume();
    }
    final started = await _beginSpeakingAt(0, locale);
    if (started) {
      isPlaying = true;
      MicCoordinator.instance.setTtsPlaybackActive(true);
      _reanchorPlayback(0);
      _startHighlightTimer();
      notifyListeners();
      unawaited(_attachVoiceAfterTtsStart());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ReadAloudUi.showVoiceControlsTip();
      });
    } else {
      isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> pauseReading(String locale) async {
    if (!isReadingSession) return;
    if (userPaused && !isPlaying) return;

    // Freeze document position before halting audio — never lose the read pointer.
    final frozen = _extrapolatedHighlightPosition();
    _segmentBaseOffset = frozen;
    _currentCharOffset = frozen;
    _reanchorPlayback(frozen);
    _applyHighlightFromEngine(frozen, frozen);

    isPlaying = false;
    userPaused = true;
    _stopHighlightTimer();
    MicCoordinator.instance.setTtsPlaybackActive(false);
    notifyListeners();

    // Halt TTS engine immediately; restore volume after the buffer stops.
    await _haltTtsEngine();
    _volumeDucked = false;
    await ensureFullVolume();
    await ReadAloudVoiceService.instance.ensurePausedListening();
    notifyListeners();
  }

  /// Attach hands-free mic after TTS has started (fallback if setStartHandler is late).
  Future<void> _attachVoiceAfterTtsStart() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!isReadingSession || userPaused || !isPlaying) return;
    await ReadingAudioSession.activateForHandsFreeReadAloud();
    _startHandsFreeVolumeKeepAlive();
    await _applyReadAloudVolume();
    onHandsFreeMicActive();
    await ReadAloudVoiceService.instance.resumeAfterTts();
  }

  Future<void> resumeReading(String locale) async {
    if (!isReadingSession || !userPaused || isPlaying) return;

    // Release mic + voice-communication audio BEFORE flipping state.
    await ReadAloudVoiceService.instance.suspendForTts();
    await ReadingAudioSession.deactivate();
    await _haltTtsEngine();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    await ReadingAudioSession.activateForHandsFreeReadAloud();
    await _configureTtsForSharedAudio();
    await MicCoordinator.instance.prepareForTtsPlayback(stopReadingVoice: true);
    await _applyVoiceOrLocale(locale);
    await _tts.setSpeechRate(speechRate);
    await _applyReadAloudVolume();

    final resumeAt = _displayCharPos.clamp(0, content!.length);
    _segmentBaseOffset = resumeAt;
    _reanchorPlayback(resumeAt);
    final started = await _beginSpeakingAt(resumeAt, locale);
    if (started) {
      userPaused = false;
      isPlaying = true;
      MicCoordinator.instance.setTtsPlaybackActive(true);
      _reanchorPlayback(resumeAt);
      _startHighlightTimer();
      notifyListeners();
      unawaited(_attachVoiceAfterTtsStart());
    } else {
      debugPrint('TtsService: resume speak failed');
      userPaused = true;
      isPlaying = false;
      unawaited(ReadAloudVoiceService.instance.resumeAfterTts());
    }
    notifyListeners();
  }

  Future<void> togglePause(String locale) async {
    if (!isReadingSession) return;
    if (isPlaying || !userPaused) {
      await pauseReading(locale);
    } else {
      await resumeReading(locale);
    }
  }

  Future<void> stop() async {
    _briefSpeaking = false;
    _stopHandsFreeVolumeKeepAlive();
    await _haltTtsEngine();
    _stopHighlightTimer();
    MicCoordinator.instance.setTtsPlaybackActive(false);
    MicCoordinator.instance.setGlobalReadingVoiceActive(false);
    unawaited(ReadingAudioSession.deactivate());
    ReadAloudUi.resetVoiceTip();
    isPlaying = false;
    userPaused = false;
    isVisible = false;
    _pendingVoiceControlsTip = false;
    title = null;
    content = null;
    progress = 0.0;
    wordStart = 0;
    wordEnd = 0;
    sentenceStart = 0;
    sentenceEnd = 0;
    _currentCharOffset = 0;
    _segmentBaseOffset = 0;
    _lastEngineCharPos = 0;
    _recentTtsSnippet = '';
    _resetSentenceTracking();
    notifyListeners();
  }

  /// Skip forward — nudge while paused, speak from new position while playing.
  Future<void> skipForward(int seconds, String locale) async {
    if (!isReadingSession) return;
    if (userPaused && !isPlaying) {
      await nudgeForward(seconds, locale);
      return;
    }
    await seekForward(seconds, locale);
  }

  /// Skip backward — nudge while paused, speak from new position while playing.
  Future<void> skipBackward(int seconds, String locale) async {
    if (!isReadingSession) return;
    if (userPaused && !isPlaying) {
      await nudgeBackward(seconds, locale);
      return;
    }
    await seekBackward(seconds, locale);
  }

  /// Move read position forward while paused (no auto-play).
  Future<void> nudgeForward(int seconds, String locale) async {
    final text = content;
    if (text == null || !isReadingSession) return;
    final charsToSkip = (speechRate * 13 * seconds).round();
    int newOffset = (_displayCharPos + charsToSkip).clamp(0, text.length - 1);
    while (newOffset < text.length && text[newOffset] != ' ') {
      newOffset++;
    }
    newOffset = (newOffset + 1).clamp(0, text.length);
    _applySeekPosition(newOffset);
    notifyListeners();
  }

  /// Move read position backward while paused (no auto-play).
  Future<void> nudgeBackward(int seconds, String locale) async {
    final text = content;
    if (text == null || !isReadingSession) return;
    final charsToSkip = (speechRate * 13 * seconds).round();
    int newOffset = (_displayCharPos - charsToSkip).clamp(0, text.length - 1);
    while (newOffset > 0 && text[newOffset] != ' ') {
      newOffset--;
    }
    newOffset = newOffset.clamp(0, text.length);
    _applySeekPosition(newOffset);
    notifyListeners();
  }

  void _applySeekPosition(int newOffset) {
    _currentCharOffset = newOffset;
    _segmentBaseOffset = newOffset;
    _lastEngineCharPos = newOffset;
    _reanchorPlayback(newOffset);
    _updateSentenceBounds(newOffset);
    userPaused = true;
    isPlaying = false;
    _stopHighlightTimer();
    MicCoordinator.instance.setTtsPlaybackActive(false);
  }

  Future<void> setRate(double rate, String locale) async {
    speechRate = rate.clamp(0.1, 2.0);
    await _tts.setSpeechRate(speechRate);
    if (isPlaying && content != null) {
      final resumeAt = _displayCharPos.clamp(0, content!.length);
      _segmentBaseOffset = resumeAt;
      _reanchorPlayback(resumeAt);
      await _safeStop();
      await _applyVoiceOrLocale(locale);
      final started = await _beginSpeakingAt(resumeAt, locale);
      if (started) {
        isPlaying = true;
        _lastEngineCharPos = resumeAt;
        _lastEngineProgressAt = DateTime.now();
        _startHighlightTimer();
        unawaited(_attachVoiceAfterTtsStart());
      }
    }
    notifyListeners();
  }

  Future<void> restart(String locale) async {
    if (content != null) {
      await play(title ?? '', content!, locale);
    }
  }

  /// Seek forward by [seconds] — approximated by skipping characters.
  /// At ~150 wpm average, 1 second ≈ 12-15 chars. We use 13.
  Future<void> seekForward(int seconds, String locale) async {
    final text = content;
    if (text == null || !isReadingSession) return;
    final charsToSkip = (speechRate * 13 * seconds).round();
    int newOffset = (_displayCharPos + charsToSkip).clamp(0, text.length);
    if (newOffset >= text.length) {
      newOffset = text.length;
      _applySeekPosition(newOffset.clamp(0, text.length - 1));
      notifyListeners();
      return;
    }
    while (newOffset < text.length && text[newOffset] != ' ') {
      newOffset++;
    }
    newOffset = (newOffset + 1).clamp(0, text.length);
    final remaining = text.substring(newOffset);
    if (remaining.trim().isEmpty) {
      _applySeekPosition(newOffset.clamp(0, text.length - 1));
      notifyListeners();
      return;
    }

    await ReadAloudVoiceService.instance.suspendForTts();
    await ReadingAudioSession.deactivate();
    await _haltTtsEngine();
    userPaused = false;
    _currentCharOffset = newOffset;
    _segmentBaseOffset = newOffset;
    _lastEngineCharPos = newOffset;
    _reanchorPlayback(newOffset);
    _updateSentenceBounds(newOffset);
    await MicCoordinator.instance.prepareForTtsPlayback(stopReadingVoice: true);
    await _applyVoiceOrLocale(locale);
    await _tts.setSpeechRate(speechRate);
    final started = await _beginSpeakingAt(newOffset, locale);
    if (started) {
      isPlaying = true;
      userPaused = false;
      MicCoordinator.instance.setTtsPlaybackActive(true);
      _startHighlightTimer();
      unawaited(_attachVoiceAfterTtsStart());
    } else {
      isPlaying = false;
      userPaused = true;
      unawaited(ReadAloudVoiceService.instance.resumeAfterTts());
    }
    notifyListeners();
  }

  /// Seek backward by [seconds].
  Future<void> seekBackward(int seconds, String locale) async {
    final text = content;
    if (text == null || !isReadingSession) return;
    final charsToSkip = (speechRate * 13 * seconds).round();
    int newOffset = (_displayCharPos - charsToSkip).clamp(0, text.length);
    if (newOffset <= 0) {
      newOffset = 0;
      _applySeekPosition(0);
      notifyListeners();
      return;
    }
    while (newOffset > 0 && text[newOffset] != ' ') {
      newOffset--;
    }
    newOffset = newOffset.clamp(0, text.length);

    await ReadAloudVoiceService.instance.suspendForTts();
    await ReadingAudioSession.deactivate();
    await _haltTtsEngine();
    userPaused = false;
    _currentCharOffset = newOffset;
    _segmentBaseOffset = newOffset;
    _lastEngineCharPos = newOffset;
    _reanchorPlayback(newOffset);
    _updateSentenceBounds(newOffset);
    await MicCoordinator.instance.prepareForTtsPlayback(stopReadingVoice: true);
    await _applyVoiceOrLocale(locale);
    await _tts.setSpeechRate(speechRate);
    final started = await _beginSpeakingAt(newOffset, locale);
    if (started) {
      isPlaying = true;
      userPaused = false;
      MicCoordinator.instance.setTtsPlaybackActive(true);
      _startHighlightTimer();
      unawaited(_attachVoiceAfterTtsStart());
    } else {
      isPlaying = false;
      userPaused = true;
      unawaited(ReadAloudVoiceService.instance.resumeAfterTts());
    }
    notifyListeners();
  }

  Future<void> showVoicePicker(BuildContext context) async {
    // Reload voices every time picker opens in case list was empty before
    if (_availableVoices.isEmpty) await _loadVoices();

    if (!context.mounted) return;

    if (_availableVoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No voices found. Install more TTS voices in your device Settings → Accessibility → Text-to-Speech.',
          ),
          backgroundColor: Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Color(0xFF141A29),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.9,
          builder: (_, controller) => Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Select Voice',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${_availableVoices.length} voices available',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: _availableVoices.length,
                  itemBuilder: (_, i) {
                    final v = _availableVoices[i];
                    final isSelected = _selectedVoice?['name'] == v['name'];
                    // Make voice name more readable
                    final displayName = v['name']!
                        .replaceAll('-', ' ')
                        .replaceAll('_', ' ');
                    return Semantics(
                      label: 'Voice $displayName, locale ${v['locale']}',
                      selected: isSelected,
                      child: ListTile(
                        minVerticalPadding: 14,
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? const Color(0xFF4B9EFF)
                              : Colors.grey[700],
                          radius: 18,
                          child: Text(
                            v['locale']!.substring(0, 2).toUpperCase(),
                            style: TextStyle(
                              color: isSelected ? Color(0xFF0A0E1A) : Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          displayName,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF4B9EFF)
                                : Colors.white,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          v['locale'] ?? '',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: Color(0xFF4B9EFF),
                              )
                            : null,
                        onTap: () {
                          setVoice(v);
                          Navigator.pop(ctx);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SentenceSpan {
  final int start;
  final int end;
  const _SentenceSpan(this.start, this.end);
}
