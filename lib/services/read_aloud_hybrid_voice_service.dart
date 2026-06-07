import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'read_aloud_kws_service.dart';
import 'read_aloud_ui.dart';
import 'read_aloud_voice_service.dart';
import 'reading_playback_state.dart';
import 'reading_voice_keyword.dart';

/// Speechify-style hybrid — no API key:
/// - **Playing** → Sherpa-ONNX keyword spotting (on-device)
/// - **Paused**  → device STT dictation (reliable continue / play)
enum ReadAloudVoiceEngine { kws, deviceStt, none }

/// Unified hands-free API used by [ReadingVoiceListener] and [TtsService].
class ReadAloudHybridVoiceService {
  ReadAloudHybridVoiceService._();
  static final ReadAloudHybridVoiceService instance =
      ReadAloudHybridVoiceService._();

  bool _sessionActive = false;
  bool _suspendedForTts = false;
  bool _openMicRequested = false;
  bool _backendTipShown = false;
  ReadAloudVoiceEngine _activeEngine = ReadAloudVoiceEngine.none;

  ReadingPlaybackState Function()? _playbackState;
  String Function()? _recentTtsSnippet;
  Future<void> Function(ReadingVoiceKeyword keyword)? _onKeyword;
  VoidCallback? _onPotentialVoiceTrigger;
  VoidCallback? _onVoiceQuiet;
  VoidCallback? _onMicReady;
  String _localeId = 'en_US';

  bool get isSessionActive => _sessionActive;
  bool get isSuspendedForTts => _suspendedForTts;
  ReadAloudVoiceEngine get activeEngine => _activeEngine;

  Future<void> startSession({
    required String localeId,
    required ReadingPlaybackState Function() playbackState,
    required String Function() recentTtsSnippet,
    required Future<void> Function(ReadingVoiceKeyword keyword) onKeyword,
    VoidCallback? onPotentialVoiceTrigger,
    VoidCallback? onVoiceQuiet,
    VoidCallback? onMicReady,
    bool openMic = true,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    _localeId = localeId;
    _playbackState = playbackState;
    _recentTtsSnippet = recentTtsSnippet;
    _onKeyword = onKeyword;
    _onPotentialVoiceTrigger = onPotentialVoiceTrigger;
    _onVoiceQuiet = onVoiceQuiet;
    _onMicReady = onMicReady;
    _sessionActive = true;
    _openMicRequested = openMic;

    unawaited(ReadAloudKwsService.instance.tryInitialize());

    if (!openMic || _suspendedForTts) return;
    await _openActiveBackend();
  }

  Future<void> stopSession() async {
    _sessionActive = false;
    _openMicRequested = false;
    _suspendedForTts = false;
    _backendTipShown = false;
    _activeEngine = ReadAloudVoiceEngine.none;
    _playbackState = null;
    _recentTtsSnippet = null;
    _onKeyword = null;
    _onPotentialVoiceTrigger = null;
    _onVoiceQuiet = null;
    _onMicReady = null;

    await ReadAloudKwsService.instance.stop();
    await ReadAloudVoiceService.instance.stopSession();
  }

  Future<void> suspendForTts() async {
    _suspendedForTts = true;
    _activeEngine = ReadAloudVoiceEngine.none;
    await ReadAloudKwsService.instance.suspend();
    await ReadAloudVoiceService.instance.suspendForTts();
  }

  Future<void> resumeAfterTts() async {
    _suspendedForTts = false;
    if (!_sessionActive) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!_sessionActive) return;
    if (!_openMicRequested) return;
    await _openActiveBackend();
  }

  Future<void> ensureListening() async {
    if (!_sessionActive || _suspendedForTts) return;
    await _openActiveBackend(force: true);
  }

  Future<void> prepareMicPermission() async {
    if (!_sessionActive) return;
    await ReadAloudVoiceService.instance.prepareMicPermission();
  }

  Future<void> _openActiveBackend({bool force = false}) async {
    if (!_sessionActive || _suspendedForTts) return;

    final state = _playbackState?.call() ?? ReadingPlaybackState.idle;
    if (state == ReadingPlaybackState.idle) return;

    final useKws = state == ReadingPlaybackState.playing &&
        await ReadAloudKwsService.instance.tryInitialize();

    if (useKws) {
      if (!force &&
          _activeEngine == ReadAloudVoiceEngine.kws &&
          ReadAloudKwsService.instance.isRunning) {
        return;
      }

      await ReadAloudVoiceService.instance.suspendForTts();
      final started = await ReadAloudKwsService.instance.start(
        onKeyword: _dispatchKeyword,
        onMicReady: _onMicReady,
        onPotentialVoiceTrigger: _onPotentialVoiceTrigger,
        onVoiceQuiet: _onVoiceQuiet,
      );

      if (started) {
        _activeEngine = ReadAloudVoiceEngine.kws;
        _showBackendTipOnce();
        return;
      }
    }

    await ReadAloudKwsService.instance.suspend();
    _activeEngine = ReadAloudVoiceEngine.deviceStt;
    _showBackendTipOnce();

    await ReadAloudVoiceService.instance.startSession(
      localeId: _localeId,
      playbackState: _playbackState!,
      recentTtsSnippet: _recentTtsSnippet!,
      onKeyword: _dispatchKeyword,
      openMic: true,
      onMicReady: _onMicReady,
      onPotentialVoiceTrigger: _onPotentialVoiceTrigger,
      onVoiceQuiet: _onVoiceQuiet,
    );
    await ReadAloudVoiceService.instance.ensureListening();
  }

  Future<void> _dispatchKeyword(ReadingVoiceKeyword keyword) async {
    final handler = _onKeyword;
    if (handler != null) {
      await handler(keyword);
    }
    if (_sessionActive && !_suspendedForTts) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      unawaited(_openActiveBackend(force: true));
    }
  }

  void _showBackendTipOnce() {
    if (_backendTipShown) return;
    _backendTipShown = true;
    final state = _playbackState?.call() ?? ReadingPlaybackState.idle;
    final tip = switch (_activeEngine) {
      ReadAloudVoiceEngine.kws =>
        'Voice (on-device): pause, play, stop, skip forward, go back',
      ReadAloudVoiceEngine.deviceStt =>
        state == ReadingPlaybackState.paused
            ? 'Voice (paused): say continue, play, forward, or back'
            : 'Voice: say pause, stop, forward, or back',
      ReadAloudVoiceEngine.none => '',
    };
    debugPrint('ReadAloudHybridVoiceService: $tip');
    ReadAloudUi.showVoiceEngineTip(tip);
  }
}
