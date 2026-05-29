import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Page-based microphone priority:
/// - [/notes] → voice notes recording / dictation
/// - [/home] → global assistant (when enabled)
/// - [/menu], [/faqs] → chatbot sheet mic
class MicCoordinator extends ChangeNotifier {
  MicCoordinator._();
  static final MicCoordinator instance = MicCoordinator._();

  final List<Future<void> Function()> _releaseHandlers = [];

  String? _currentRoute;
  bool _notesRecordingActive = false;
  bool _chatbotSheetOpen = false;
  bool _chatbotListening = false;

  String? get currentRoute => _currentRoute;
  bool get notesRecordingActive => _notesRecordingActive;
  bool get chatbotSheetOpen => _chatbotSheetOpen;
  bool get chatbotListening => _chatbotListening;

  /// Home assistant may use the mic (only on home route).
  bool get assistantMayListen =>
      _currentRoute == '/home' &&
      !_notesRecordingActive &&
      !_chatbotListening &&
      !_chatbotSheetOpen;

  /// Chatbot mic on Menu / FAQs (blocks assistant everywhere else on those routes).
  bool get chatbotMayListen =>
      (_currentRoute == '/menu' || _currentRoute == '/faqs') &&
      !_notesRecordingActive;

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

    // Leaving home or entering a higher-priority screen → release assistant.
    if (normalized == '/notes' ||
        normalized == '/menu' ||
        normalized == '/faqs') {
      unawaited(releaseAll());
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

  Future<void> releaseAll() async {
    for (final release in List<Future<void> Function()>.from(_releaseHandlers)) {
      try {
        await release();
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
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
