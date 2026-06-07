import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../language_provider.dart';
import '../navigation_keys.dart';
import '../tts_service.dart';
import 'headphone_audio_detector.dart';
import 'mic_coordinator.dart';
import 'read_aloud_ui.dart';
import 'read_aloud_voice_service.dart';
import 'reading_playback_state.dart';
import 'reading_voice_controller.dart';
import 'reading_voice_keyword.dart';

/// Hands-free read-aloud via device STT — optimized for earphones / headphones.
class ReadingVoiceListener {
  ReadingVoiceListener({required this.hostState});

  final State hostState;
  bool _handlingCommand = false;
  bool _tipShown = false;

  bool get mounted => hostState.mounted;

  BuildContext get context => hostState.context;

  Future<void> init() async {
    await HeadphoneAudioDetector.instance.init();
    MicCoordinator.instance.addListener(_onCoordinatorChanged);
    _syncFromTts();
  }

  void dispose() {
    MicCoordinator.instance.removeListener(_onCoordinatorChanged);
    unawaited(ReadAloudVoiceService.instance.stopSession());
  }

  void onTtsChanged() {
    if (!mounted) return;
    _syncFromTts();
  }

  void onMicChanged() => _syncFromTts();

  void _onCoordinatorChanged() => _syncFromTts();

  void _syncFromTts() {
    if (!mounted) return;
    unawaited(_syncFromTtsAsync());
  }

  Future<void> _syncFromTtsAsync() async {
    if (!mounted) return;
    await HeadphoneAudioDetector.instance.refresh();
    if (!mounted) return;

    final tts = context.read<TtsService>();
    final shouldListen = tts.isReadingSession;
    MicCoordinator.instance.setGlobalReadingVoiceActive(shouldListen);

    if (!shouldListen) {
      unawaited(ReadAloudVoiceService.instance.stopSession());
      _tipShown = false;
      return;
    }

    if (!MicCoordinator.instance.globalReadingVoiceMayListen) return;

    final openMic = (tts.isPlaying || tts.userPaused) &&
        !ReadAloudVoiceService.instance.isSuspendedForTts;

    await _startVoiceSession(openMic: openMic);
  }

  Future<void> _startVoiceSession({required bool openMic}) async {
    if (!mounted || !MicCoordinator.instance.globalReadingVoiceMayListen) {
      return;
    }

    final tts = context.read<TtsService>();
    final locale = context.read<LanguageProvider>().sttLocale;
    final headphones = HeadphoneAudioDetector.instance.isHeadphonesConnected;

    await ReadAloudVoiceService.instance.startSession(
      localeId: locale,
      playbackState: () => tts.playbackState,
      recentTtsSnippet: () => tts.recentTtsSnippet,
      onKeyword: _onKeyword,
      openMic: openMic,
      onMicReady: () {
        if (!mounted) return;
        final ttsNow = context.read<TtsService>();
        if (ttsNow.userPaused || !ttsNow.isPlaying) return;
        ttsNow.onHandsFreeMicActive();
      },
      onPotentialVoiceTrigger: () {
        if (!mounted || headphones) return;
        context.read<TtsService>().duckVolumeForVoiceCommands();
      },
      onVoiceQuiet: () {
        if (!mounted || headphones) return;
        unawaited(context.read<TtsService>().restoreVolumeAfterVoiceCommands());
      },
    );

    if (!openMic) return;

    if (tts.isPlaying) {
      tts.onHandsFreeMicActive();
    }
    if (tts.userPaused) {
      await ReadAloudVoiceService.instance.ensurePausedListening();
      ReadAloudUi.showVoiceEngineTip(ReadAloudUi.voiceControlsPausedTip);
    } else if (!_tipShown) {
      _tipShown = true;
      final tip = headphones
          ? ReadAloudUi.voiceControlsPlayingHeadphoneTip
          : ReadAloudUi.voiceControlsPlayingSpeakerTip;
      ReadAloudUi.showVoiceEngineTip(tip);
    }
  }

  Future<void> _onKeyword(ReadingVoiceKeyword keyword) async {
    if (!mounted || _handlingCommand) return;
    if (!MicCoordinator.instance.globalReadingVoiceMayListen) return;

    _handlingCommand = true;
    final tts = context.read<TtsService>();
    final locale = context.read<LanguageProvider>().ttsLocale;
    final headphones = HeadphoneAudioDetector.instance.isHeadphonesConnected;

    final dispatch = await ReadingVoiceController.instance.dispatch(
      keyword: keyword,
      tts: tts,
      locale: locale,
    );

    if (mounted && dispatch.handled) {
      ReadAloudUi.showFeedback(ReadingVoiceKeywordSpotter.feedbackFor(keyword));
      if (dispatch.closeReader) {
        final nav = globalNavigatorKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        }
      } else if (!headphones &&
          keyword != ReadingVoiceKeyword.pause &&
          keyword != ReadingVoiceKeyword.stop &&
          tts.isPlaying) {
        unawaited(tts.restoreVolumeAfterVoiceCommands());
      }
    }

    _handlingCommand = false;
  }
}
