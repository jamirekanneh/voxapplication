import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'app_speech_service.dart';
import 'headphone_audio_detector.dart';
import 'read_aloud_ui.dart';
import 'reading_audio_session.dart';
import 'reading_playback_state.dart';
import 'reading_voice_keyword.dart';

/// Speechify-style hands-free read-aloud: continuous device STT + tail keyword matching.
/// No API key, no model download — uses the phone's built-in speech recognizer.
class ReadAloudVoiceService {
  ReadAloudVoiceService._();
  static final ReadAloudVoiceService instance = ReadAloudVoiceService._();

  static const _owner = 'reading';

  bool _sessionActive = false;
  bool _startingListen = false;
  bool _suspendedForTts = false;
  bool _micPermissionDenied = false;
  String _localeId = 'en_US';
  String _commandLanguage = 'English';
  String _lastTranscript = '';
  ReadingPlaybackState? _listeningForState;

  ReadingPlaybackState Function()? _playbackState;
  String Function()? _recentTtsSnippet;
  Future<void> Function(ReadingVoiceKeyword keyword)? _onKeyword;
  VoidCallback? _onPotentialVoiceTrigger;
  VoidCallback? _onVoiceQuiet;
  VoidCallback? _onMicReady;

  bool get isSessionActive => _sessionActive;
  bool get isSuspendedForTts => _suspendedForTts;

  Future<void> startSession({
    required String localeId,
    String commandLanguage = 'English',
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
    _commandLanguage = commandLanguage;
    _playbackState = playbackState;
    _recentTtsSnippet = recentTtsSnippet;
    _onKeyword = onKeyword;
    _onPotentialVoiceTrigger = onPotentialVoiceTrigger;
    _onVoiceQuiet = onVoiceQuiet;
    _onMicReady = onMicReady;
    _sessionActive = true;

    final state = _playbackState?.call();
    if (state == ReadingPlaybackState.paused) {
      _listeningForState = null;
      _suspendedForTts = false;
    }

    if (!openMic || _suspendedForTts) return;
    await _openMic();
  }

  /// Reliable mic while paused — continue, play, and stop (speaker or earphones).
  Future<void> ensurePausedListening() async {
    if (!_sessionActive) return;
    _suspendedForTts = false;
    _listeningForState = null;
    _lastTranscript = '';
    await ReadingAudioSession.activateForPausedVoiceCommands();
    await _ensureListening();
  }

  Future<void> _openMicForPlaybackState() async {
    if (!_sessionActive || _suspendedForTts) return;
    _lastTranscript = '';
    final state = _playbackState?.call() ?? ReadingPlaybackState.idle;
    if (state == ReadingPlaybackState.paused) {
      await ReadingAudioSession.activateForPausedVoiceCommands();
    } else if (HeadphoneAudioDetector.instance.isHeadphonesConnected) {
      await ReadingAudioSession.activateForHeadphoneReadAloud();
    } else {
      await ReadingAudioSession.activateForHandsFreeReadAloud();
    }
    await _ensureListening();
  }

  Future<void> _openMic() async => _openMicForPlaybackState();

  Future<void> stopSession() async {
    _sessionActive = false;
    _playbackState = null;
    _recentTtsSnippet = null;
    _onKeyword = null;
    _onPotentialVoiceTrigger = null;
    _onVoiceQuiet = null;
    _onMicReady = null;
    _lastTranscript = '';
    _listeningForState = null;
    _micPermissionDenied = false;
    if (AppSpeechService.instance.activeOwner == _owner) {
      await AppSpeechService.instance.stop();
    }
    await ReadingAudioSession.deactivate();
  }

  /// Release the mic while TTS starts speaking (Android cannot share reliably).
  Future<void> suspendForTts() async {
    _suspendedForTts = true;
    if (AppSpeechService.instance.activeOwner == _owner) {
      await AppSpeechService.instance.stop();
    }
  }

  /// Yield the mic to assistant / search / notes without blocking reclaim after they finish.
  Future<void> yieldMicToOtherFeature() async {
    _listeningForState = null;
    if (AppSpeechService.instance.activeOwner == _owner) {
      await AppSpeechService.instance.stop();
    }
  }

  /// Re-attach hands-free listening after TTS audio has started.
  Future<void> resumeAfterTts() async {
    _suspendedForTts = false;
    if (!_sessionActive) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!_sessionActive) return;
    final state = _playbackState?.call();
    if (state == ReadingPlaybackState.paused) {
      await ensurePausedListening();
      return;
    }
    await _openMicForPlaybackState();
  }

  Future<void> ensureListening() async {
    if (!_sessionActive || _suspendedForTts) return;
    await _ensureListening();
  }

  /// Prompt for mic access as soon as a read-aloud session opens.
  Future<void> prepareMicPermission() async {
    if (!_sessionActive) return;
    await _ensureMicPermission();
  }

  Future<bool> _ensureMicPermission() async {
    if (_micPermissionDenied) return false;
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (!status.isGranted) {
      _micPermissionDenied = true;
      debugPrint('ReadAloudVoiceService: microphone permission denied');
      ReadAloudUi.showFeedback(
        'Allow microphone access in Settings for voice controls',
      );
      return false;
    }
    return true;
  }

  Future<void> _ensureListening() async {
    if (!_sessionActive || _startingListen || _suspendedForTts) return;

    final state = _playbackState?.call() ?? ReadingPlaybackState.idle;
    if (state == ReadingPlaybackState.idle) return;

    if (AppSpeechService.instance.activeOwner == _owner &&
        AppSpeechService.instance.isListening &&
        _listeningForState == state) {
      return;
    }

    if (!await _ensureMicPermission()) return;

    _startingListen = true;
    try {
      if (AppSpeechService.instance.isListening) {
        await AppSpeechService.instance.stop();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      _listeningForState = state;
      final headphones = HeadphoneAudioDetector.instance.isHeadphonesConnected;
      final paused = state == ReadingPlaybackState.paused;
      // Earphones: dictation while playing — mic hears user, not TTS in headphones.
      final useDictation = paused || headphones;
      final started = await AppSpeechService.instance.handoffListen(
        owner: _owner,
        localeId: _localeId,
        listenFor: const Duration(hours: 8),
        pauseFor: useDictation
            ? const Duration(seconds: 4)
            : const Duration(milliseconds: 1500),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode:
              useDictation ? stt.ListenMode.dictation : stt.ListenMode.search,
        ),
        onResult: _onSpeechResult,
        onStatus: (status) {
          if (!_sessionActive) return;
          if (status == 'done' || status == 'notListening') {
            unawaited(Future<void>.delayed(const Duration(milliseconds: 250), () {
              if (_sessionActive) unawaited(_ensureListening());
            }));
          }
        },
        onError: (_) {
          if (!_sessionActive) return;
          unawaited(Future<void>.delayed(const Duration(milliseconds: 600), () {
            if (_sessionActive) unawaited(_ensureListening());
          }));
        },
      );

      if (!started && _sessionActive) {
        _listeningForState = null;
        debugPrint('ReadAloudVoiceService: STT listen failed');
        ReadAloudUi.showFeedback(
          ReadAloudUi.translate('voice_controls_unavailable'),
        );
      } else {
        debugPrint(
          'ReadAloudVoiceService: listening ($state) for pause / play / stop',
        );
        _onMicReady?.call();
      }
    } finally {
      _startingListen = false;
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!_sessionActive) return;

    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;

    final state = _playbackState?.call() ?? ReadingPlaybackState.idle;
    final hadSpeech = words != _lastTranscript;
    _lastTranscript = words;
    final headphones = HeadphoneAudioDetector.instance.isHeadphonesConnected;

    if (state == ReadingPlaybackState.playing && hadSpeech && !headphones) {
      _onPotentialVoiceTrigger?.call();
    }

    // Fast barge-in while TTS is playing (partial STT).
    if (state == ReadingPlaybackState.playing) {
      if (ReadingVoiceKeywordSpotter.spot(
            spoken: words,
            state: ReadingPlaybackState.playing,
            commandLanguage: _commandLanguage,
            ignoreTtsEcho: true,
          ) ==
          ReadingVoiceKeyword.stop) {
        unawaited(_dispatchKeyword(ReadingVoiceKeyword.stop));
        return;
      }
      if (ReadingVoiceKeywordSpotter.spot(
            spoken: words,
            state: ReadingPlaybackState.playing,
            commandLanguage: _commandLanguage,
            ignoreTtsEcho: true,
          ) ==
          ReadingVoiceKeyword.pause) {
        unawaited(_dispatchKeyword(ReadingVoiceKeyword.pause));
        return;
      }
      final seekWhilePlaying = ReadingVoiceKeywordSpotter.spotSeekOnly(
        words,
        commandLanguage: _commandLanguage,
      );
      if (seekWhilePlaying != null) {
        unawaited(_dispatchKeyword(seekWhilePlaying));
        return;
      }
      final highlightWhilePlaying = ReadingVoiceKeywordSpotter.spotHighlightOnly(
        words,
        commandLanguage: _commandLanguage,
      );
      if (highlightWhilePlaying != null) {
        unawaited(_dispatchKeyword(highlightWhilePlaying));
        return;
      }
    }

    // Fast commands while paused — continue / play / stop (always, with or without earphones).
    if (state == ReadingPlaybackState.paused) {
      if (ReadingVoiceKeywordSpotter.spot(
            spoken: words,
            state: state,
            commandLanguage: _commandLanguage,
            ignoreTtsEcho: true,
          ) ==
          ReadingVoiceKeyword.stop) {
        unawaited(_dispatchKeyword(ReadingVoiceKeyword.stop));
        return;
      }
      if (ReadingVoiceKeywordSpotter.spot(
            spoken: words,
            state: state,
            commandLanguage: _commandLanguage,
            ignoreTtsEcho: true,
          ) ==
          ReadingVoiceKeyword.play) {
        unawaited(_dispatchKeyword(ReadingVoiceKeyword.play));
        return;
      }
      final seekWhilePaused = ReadingVoiceKeywordSpotter.spotSeekOnly(
        words,
        commandLanguage: _commandLanguage,
      );
      if (seekWhilePaused != null) {
        unawaited(_dispatchKeyword(seekWhilePaused));
        return;
      }
      final highlightWhilePaused = ReadingVoiceKeywordSpotter.spotHighlightOnly(
        words,
        commandLanguage: _commandLanguage,
      );
      if (highlightWhilePaused != null) {
        unawaited(_dispatchKeyword(highlightWhilePaused));
        return;
      }
    }

    final keyword = ReadingVoiceKeywordSpotter.spot(
      spoken: words,
      state: state,
      commandLanguage: _commandLanguage,
      recentTtsSnippet: _recentTtsSnippet?.call() ?? '',
      ignoreTtsEcho: headphones,
    );

    if (keyword == null) return;

    debugPrint('ReadAloudVoiceService heard "$words" → $keyword');
    _lastTranscript = '';
    _onVoiceQuiet?.call();

    unawaited(_dispatchKeyword(keyword));
  }

  Future<void> _dispatchKeyword(ReadingVoiceKeyword keyword) async {
    if (!_sessionActive) return;

    _listeningForState = null;
    if (AppSpeechService.instance.activeOwner == _owner) {
      await AppSpeechService.instance.stop();
    }

    final handler = _onKeyword;
    if (handler != null) {
      await handler(keyword);
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (_sessionActive && !_suspendedForTts) {
      unawaited(_ensureListening());
    }
  }
}
