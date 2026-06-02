import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Page-based microphone priority:
/// - [/notes] → voice notes recording / dictation
/// - [/home] → global assistant (when enabled) OR library search mic
/// - [/dictionary] → dictionary search mic
/// - chatbot / study-buddy sheet → mic while sheet is open
/// - [/menu], [/faqs] → floating chatbot mic
class MicCoordinator extends ChangeNotifier {
  MicCoordinator._();
  static final MicCoordinator instance = MicCoordinator._();

  final List<Future<void> Function()> _releaseHandlers = [];

  String? _currentRoute;
  bool _notesRecordingActive = false;
  bool _chatbotSheetOpen = false;
  bool _chatbotListening = false;
  bool _searchMicActive = false;
  bool _readerVoiceActive = false;
  bool _assistantMicActive = false;
  bool _ttsPlaybackActive = false;

  String? get currentRoute => _currentRoute;
  bool get notesRecordingActive => _notesRecordingActive;
  bool get chatbotSheetOpen => _chatbotSheetOpen;
  bool get chatbotListening => _chatbotListening;
  bool get searchMicActive => _searchMicActive;
  bool get readerVoiceActive => _readerVoiceActive;
  bool get assistantMicActive => _assistantMicActive;
  bool get ttsPlaybackActive => _ttsPlaybackActive;

  /// Global assistant STT — only after user taps Assistant (not while TTS plays).
  bool get assistantMayListen =>
      _assistantMicActive &&
      _currentRoute == '/home' &&
      !_notesRecordingActive &&
      !_chatbotListening &&
      !_chatbotSheetOpen &&
      !_searchMicActive &&
      !_readerVoiceActive &&
      !_ttsPlaybackActive;

  /// Search-bar mic on Home / Dictionary.
  bool get searchMicMayListen =>
      (_currentRoute == '/home' || _currentRoute == '/dictionary') &&
      !_notesRecordingActive &&
      !_chatbotListening &&
      !_chatbotSheetOpen &&
      !_readerVoiceActive;

  /// Chatbot / study-buddy mic when sheet is open (not during notes recording).
  bool get chatbotMayListen =>
      !_notesRecordingActive &&
      (_chatbotSheetOpen ||
          _currentRoute == '/menu' ||
          _currentRoute == '/faqs');

  /// Voice notes recording / dictation on Notes page.
  bool get notesMayUseMic =>
      _currentRoute == '/notes' || _notesRecordingActive;

  void registerReleaseHandler(Future<void> Function() handler) {
    if (!_releaseHandlers.contains(handler)) {
      _releaseHandlers.add(handler);
    }
  }

  void unregisterReleaseHandler(Future<void> Function() handler) {
    _releaseHandlers.remove(handler);
  }

  void setRoute(String? routeName) {
    final normalized = routeName?.isEmpty == true ? null : routeName;
    if (_currentRoute == normalized) return;
    _currentRoute = normalized;

    // Stop assistant / other mics when leaving home or entering higher-priority routes.
    if (normalized == '/notes' ||
        normalized == '/menu' ||
        normalized == '/faqs') {
      unawaited(releaseAll());
    } else if (normalized == '/dictionary') {
      // Stop home assistant only; dictionary search mic manages itself.
      unawaited(releaseAll(skipSearchMic: true));
    }

    if (normalized != '/home' && normalized != '/dictionary') {
      _searchMicActive = false;
    }
    notifyListeners();
  }

  void setNotesRecordingActive(bool active) {
    if (_notesRecordingActive == active) return;
    _notesRecordingActive = active;
    if (active) unawaited(releaseAll());
    notifyListeners();
  }

  void setChatbotSheetOpen(bool open) {
    if (_chatbotSheetOpen == open) return;
    _chatbotSheetOpen = open;
    if (open) unawaited(releaseAll());
    notifyListeners();
  }

  void setChatbotListening(bool listening) {
    if (_chatbotListening == listening) return;
    _chatbotListening = listening;
    notifyListeners();
  }

  /// Marks search mic session without re-calling [releaseAll] (avoids killing the new session).
  void setSearchMicActive(bool active) {
    if (_searchMicActive == active) return;
    _searchMicActive = active;
    if (active) {
      _assistantMicActive = false;
      _ttsPlaybackActive = false;
    }
    notifyListeners();
  }

  /// Reader hands-free commands own the mic (blocks assistant on Home).
  void setReaderVoiceActive(bool active) {
    if (_readerVoiceActive == active) return;
    _readerVoiceActive = active;
    if (active) {
      _assistantMicActive = false;
      unawaited(releaseAll(skipSearchMic: true));
    }
    notifyListeners();
  }

  /// User tapped Assistant on Home (or double-tap) — allow global STT.
  void setAssistantMicActive(bool active) {
    if (_assistantMicActive == active) return;
    _assistantMicActive = active;
    if (active) {
      _ttsPlaybackActive = false;
      unawaited(releaseAll());
    } else {
      unawaited(releaseAll());
    }
    notifyListeners();
  }

  /// Document read-aloud (TTS) — no STT; release mics for speaker output.
  Future<void> prepareForTtsPlayback() async {
    _ttsPlaybackActive = true;
    _assistantMicActive = false;
    await releaseAll();
    notifyListeners();
  }

  void setTtsPlaybackActive(bool active) {
    if (_ttsPlaybackActive == active) return;
    _ttsPlaybackActive = active;
    notifyListeners();
  }

  /// Stops assistant/chatbot/notes mics, then optional short pause for the OS audio stack.
  Future<void> prepareForSearchMic(
    Future<void> Function() searchReleaseHandler,
  ) async {
    unregisterReleaseHandler(searchReleaseHandler);
    await releaseAll(skipSearchMic: true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    registerReleaseHandler(searchReleaseHandler);
    setSearchMicActive(true);
  }

  Future<void> releaseAll({bool skipSearchMic = false}) async {
    for (final release in List<Future<void> Function()>.from(_releaseHandlers)) {
      try {
        await release();
      } catch (_) {}
    }
    if (!skipSearchMic) {
      _searchMicActive = false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  /// Notes file recording: release other mic users, then OS + recorder permission.
  Future<bool> prepareForFileRecording(AudioRecorder recorder) async {
    if (!notesMayUseMic) return false;
    await releaseAll();

    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (!status.isGranted) return false;

    return recorder.hasPermission(request: true);
  }
}
