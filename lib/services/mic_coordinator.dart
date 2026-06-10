import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'app_speech_service.dart';

/// Page-based microphone priority:
/// - Read-aloud voice (playing or paused session) → hands-free pause/play/seek
/// - Double-tap / Assistant toggle → global assistant (when read-aloud inactive)
/// - [/notes] → voice notes recording / dictation
/// - [/home] → library search mic
/// - [/dictionary] → dictionary search mic
/// - chatbot / study-buddy sheet → mic while sheet is open
class MicCoordinator extends ChangeNotifier {
  MicCoordinator._();
  static final MicCoordinator instance = MicCoordinator._();

  static const _assistantOwner = 'assistant';
  static const _readingOwner = 'reading';

  final List<Future<void> Function()> _releaseHandlers = [];

  String? _currentRoute;
  bool _notesRecordingActive = false;
  bool _chatbotSheetOpen = false;
  bool _chatbotListening = false;
  bool _searchMicActive = false;
  bool _readerVoiceActive = false;
  bool _globalReadingVoiceActive = false;
  bool _assistantMicActive = false;
  bool _ttsPlaybackActive = false;
  bool _authFlowActive = false;
  bool _externalCaptureActive = false;

  /// Registered by [GlobalSttWrapper] so overlays (chat sheets) can trigger assistant.
  Future<void> Function({bool manual})? requestAssistantListen;

  String? get currentRoute => _currentRoute;
  bool get notesRecordingActive => _notesRecordingActive;
  bool get chatbotSheetOpen => _chatbotSheetOpen;
  bool get chatbotListening => _chatbotListening;
  bool get searchMicActive => _searchMicActive;
  bool get readerVoiceActive => _readerVoiceActive;
  bool get globalReadingVoiceActive => _globalReadingVoiceActive;
  bool get assistantMicActive => _assistantMicActive;
  bool get ttsPlaybackActive => _ttsPlaybackActive;
  bool get authFlowActive => _authFlowActive;

  /// Camera / gallery capture — blocks all mics until [endExternalCapture].
  bool get externalCaptureActive => _externalCaptureActive;

  /// True while read-aloud TTS audio is playing.
  bool get readAloudMicReserved => _ttsPlaybackActive;

  /// Read-aloud session owns hands-free voice controls (playing or paused).
  bool get readAloudVoiceSessionActive => _globalReadingVoiceActive;

  /// Mini-player session is paused — assistant / search / notes / chat may borrow the mic.
  bool get readAloudPausedYield =>
      _globalReadingVoiceActive && !_ttsPlaybackActive;

  /// While TTS plays, block assistant and page mics; when paused they may listen.
  bool get readAloudBlocksOtherMics =>
      _globalReadingVoiceActive && _ttsPlaybackActive;

  /// Hands-free read-aloud (pause / play / seek / highlight) when nothing else holds the mic.
  bool get globalReadingVoiceMayListen =>
      !_externalCaptureActive &&
      _globalReadingVoiceActive &&
      !_assistantMicActive &&
      !_searchMicActive &&
      !_notesRecordingActive &&
      !_chatbotListening &&
      !_chatbotSheetOpen;

  /// Assistant — blocked while read-aloud TTS is playing or during auth/profile.
  bool get assistantMayListen =>
      !_externalCaptureActive &&
      _assistantMicActive &&
      !readAloudBlocksOtherMics &&
      !_authFlowActive;

  /// Whether the user can activate the global assistant right now.
  bool get assistantMayActivate =>
      !_externalCaptureActive &&
      !readAloudBlocksOtherMics &&
      !_authFlowActive;

  /// Search mic — allowed when read-aloud is paused (mini player).
  bool get searchMicMayListen =>
      !_externalCaptureActive &&
      (_currentRoute == '/home' || _currentRoute == '/dictionary') &&
      !_assistantMicActive &&
      !_notesRecordingActive &&
      !_chatbotListening &&
      !_chatbotSheetOpen &&
      !readAloudBlocksOtherMics;

  /// Chatbot / study-buddy — allowed when read-aloud is paused.
  bool get chatbotMayListen =>
      !_externalCaptureActive &&
      !_assistantMicActive &&
      !_notesRecordingActive &&
      !readAloudBlocksOtherMics &&
      (_chatbotSheetOpen ||
          _currentRoute == '/menu' ||
          _currentRoute == '/faqs');

  /// Notes dictation / recording — blocked only while read-aloud TTS is playing.
  bool get notesMayUseMic =>
      !_externalCaptureActive &&
      !_assistantMicActive &&
      !readAloudBlocksOtherMics &&
      (_currentRoute == '/notes' || _notesRecordingActive);

  void registerReleaseHandler(Future<void> Function() handler) {
    if (!_releaseHandlers.contains(handler)) {
      _releaseHandlers.add(handler);
    }
  }

  void unregisterReleaseHandler(Future<void> Function() handler) {
    _releaseHandlers.remove(handler);
  }

  /// Suspend assistant + release all mics during logout / profile sign-in.
  Future<void> enterAuthFlow() async {
    if (_authFlowActive) {
      _assistantMicActive = false;
      await releaseAll();
      notifyListeners();
      return;
    }
    _authFlowActive = true;
    _assistantMicActive = false;
    _searchMicActive = false;
    _chatbotListening = false;
    await releaseAll();
    notifyListeners();
  }

  void exitAuthFlow() {
    if (!_authFlowActive) return;
    _authFlowActive = false;
    notifyListeners();
  }

  void setRoute(String? routeName) {
    final normalized = routeName?.isEmpty == true ? null : routeName;
    if (_currentRoute == normalized) return;
    _currentRoute = normalized;

    if (normalized == '/home') {
      exitAuthFlow();
    }

    if (normalized == '/notes' ||
        normalized == '/menu' ||
        normalized == '/faqs') {
      unawaited(releaseAll(keepReadingVoice: _globalReadingVoiceActive));
    } else if (normalized == '/dictionary') {
      unawaited(releaseAll(skipSearchMic: true, keepReadingVoice: _globalReadingVoiceActive));
    }

    if (normalized != '/home' && normalized != '/dictionary') {
      _searchMicActive = false;
    }
    notifyListeners();
  }

  void syncRouteIfCurrent(BuildContext context, String routeName) {
    final route = ModalRoute.of(context);
    if (route?.isCurrent == true) {
      setRoute(routeName);
    }
  }

  void setNotesRecordingActive(bool active) {
    if (_notesRecordingActive == active) return;
    _notesRecordingActive = active;
    if (active) {
      _assistantMicActive = false;
      _searchMicActive = false;
      _chatbotListening = false;
      unawaited(AppSpeechService.instance.stopUnlessOwner(_readingOwner));
    } else {
      unawaited(releaseAll(skipSearchMic: true));
    }
    notifyListeners();
  }

  void setChatbotSheetOpen(bool open) {
    if (_chatbotSheetOpen == open) return;
    _chatbotSheetOpen = open;
    if (open) {
      unawaited(releaseAll(keepReadingVoice: _globalReadingVoiceActive));
    }
    notifyListeners();
  }

  void setChatbotListening(bool listening) {
    if (_chatbotListening == listening) return;
    _chatbotListening = listening;
    notifyListeners();
  }

  void setSearchMicActive(bool active) {
    if (_searchMicActive == active) return;
    _searchMicActive = active;
    if (active) {
      _assistantMicActive = false;
    }
    notifyListeners();
  }

  void setReaderVoiceActive(bool active) {
    if (_readerVoiceActive == active) return;
    _readerVoiceActive = active;
    if (active) {
      _assistantMicActive = false;
    }
    notifyListeners();
  }

  void setGlobalReadingVoiceActive(bool active) {
    if (_globalReadingVoiceActive == active) return;
    _globalReadingVoiceActive = active;
    if (active) {
      _assistantMicActive = false;
      _searchMicActive = false;
      _chatbotListening = false;
      unawaited(AppSpeechService.instance.stopUnlessOwner(_readingOwner));
    }
    notifyListeners();
  }

  void setAssistantMicActive(bool active) {
    if (_assistantMicActive == active) return;
    if (active && !assistantMayActivate) return;

    _assistantMicActive = active;
    if (active) {
      _searchMicActive = false;
      _chatbotListening = false;
      _readerVoiceActive = false;
      unawaited(_releaseForAssistantActivation());
    } else {
      unawaited(AppSpeechService.instance.stopUnlessOwner(_assistantOwner));
    }
    notifyListeners();
  }

  Future<void> activateAssistant({bool manual = true}) async {
    if (!assistantMayActivate) return;
    await requestAssistantListen?.call(manual: manual);
  }

  /// Page mic buttons call this to take the mic from assistant without full teardown.
  Future<void> yieldFromAssistant() async {
    if (!_assistantMicActive) return;
    _assistantMicActive = false;
    await AppSpeechService.instance.stopUnlessOwner(_assistantOwner);
    notifyListeners();
  }

  Future<void> _releaseForAssistantActivation() async {
    await AppSpeechService.instance.stopUnlessOwner(_readingOwner);
    for (final release in List<Future<void> Function()>.from(_releaseHandlers)) {
      try {
        await release();
      } catch (_) {}
    }
    _searchMicActive = false;
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  /// Document read-aloud — release page mics before TTS speaks.
  /// Release page / assistant mics before read-aloud resumes from the mini player.
  Future<void> reclaimMicForReadAloudPlayback() async {
    await yieldFromAssistant();
    _searchMicActive = false;
    _chatbotListening = false;
    for (final release in List<Future<void> Function()>.from(_releaseHandlers)) {
      try {
        await release();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> prepareForTtsPlayback({bool stopReadingVoice = false}) async {
    await reclaimMicForReadAloudPlayback();
    _ttsPlaybackActive = true;
    if (stopReadingVoice) {
      await AppSpeechService.instance.stop();
    } else {
      await AppSpeechService.instance.stopUnlessOwner(_readingOwner);
    }
    notifyListeners();
  }

  void setTtsPlaybackActive(bool active) {
    if (_ttsPlaybackActive == active) return;
    _ttsPlaybackActive = active;
    notifyListeners();
  }

  Future<void> prepareForSearchMic(
    Future<void> Function() searchReleaseHandler,
  ) async {
    await yieldFromAssistant();
    unregisterReleaseHandler(searchReleaseHandler);
    await releaseAll(
      skipSearchMic: true,
      keepReadingVoice: _globalReadingVoiceActive,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    registerReleaseHandler(searchReleaseHandler);
    setSearchMicActive(true);
  }

  /// Release every mic/TTS audio holder before camera or gallery capture.
  Future<void> beginExternalCapture() async {
    if (_externalCaptureActive) return;
    _externalCaptureActive = true;
    _assistantMicActive = false;
    _searchMicActive = false;
    _chatbotListening = false;
    _readerVoiceActive = false;
    _globalReadingVoiceActive = false;
    _ttsPlaybackActive = false;
    notifyListeners();

    await yieldFromAssistant();
    await releaseAll();
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Future<void> endExternalCapture() async {
    if (!_externalCaptureActive) return;
    _externalCaptureActive = false;
    notifyListeners();
  }

  Future<void> releaseAll({
    bool skipSearchMic = false,
    bool keepReadingVoice = false,
  }) async {
    if (keepReadingVoice) {
      await AppSpeechService.instance.stopUnlessOwner(_readingOwner);
    } else {
      await AppSpeechService.instance.stop();
    }
    for (final release in List<Future<void> Function()>.from(_releaseHandlers)) {
      try {
        await release();
      } catch (_) {}
    }
    if (!skipSearchMic) {
      _searchMicActive = false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  Future<bool> prepareForFileRecording(AudioRecorder recorder) async {
    await yieldFromAssistant();
    if (_currentRoute != '/notes') return false;
    await releaseAll();

    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (!status.isGranted) return false;

    return recorder.hasPermission(request: true);
  }
}
