import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Single shared speech-to-text engine for the whole app.
/// Android allows only one active STT session — multiple [SpeechToText]
/// instances break every mic (assistant, search, chatbot, read-aloud, notes).
class AppSpeechService {
  AppSpeechService._();
  static final AppSpeechService instance = AppSpeechService._();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;
  String? _activeOwner;

  void Function(String)? _onStatus;
  void Function(dynamic)? _onError;

  bool get isAvailable => _initialized;
  bool get isListening => _speech.isListening;
  String? get activeOwner => _activeOwner;

  Future<bool> ensureInitialized({
    String? owner,
    void Function(String)? onStatus,
    void Function(dynamic)? onError,
  }) async {
    if (owner != null) {
      _onStatus = onStatus ?? _onStatus;
      _onError = onError ?? _onError;
    }

    if (_initialized) return true;

    _onStatus = onStatus;
    _onError = onError;
    _initialized = await _speech.initialize(
      onError: (e) => _onError?.call(e),
      onStatus: (s) => _onStatus?.call(s),
    );
    if (!_initialized) {
      debugPrint('AppSpeechService: STT not available on this device');
    }
    return _initialized;
  }

  void setCallbacks({
    required String owner,
    void Function(String)? onStatus,
    void Function(dynamic)? onError,
  }) {
    if (_activeOwner == null || _activeOwner == owner) {
      _onStatus = onStatus;
      _onError = onError;
    }
  }

  /// Stop STT unless [owner] currently owns the mic (smooth read-aloud handoff).
  Future<void> stopUnlessOwner(String owner) async {
    if (_activeOwner == owner) return;
    await stop();
  }

  Future<void> stop() async {
    _activeOwner = null;
    try {
      await _speech.stop();
      await _speech.cancel();
    } catch (_) {}
  }

  /// Switch mic owner with a short gap for the OS audio stack.
  Future<bool> handoffListen({
    required String owner,
    required stt.SpeechResultListener onResult,
    String? localeId,
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 2),
    stt.SpeechListenOptions? listenOptions,
    void Function(String)? onStatus,
    void Function(dynamic)? onError,
  }) async {
    if (_activeOwner == owner && _speech.isListening) return true;
    if (_speech.isListening) {
      await stop();
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return listen(
      owner: owner,
      onResult: onResult,
      localeId: localeId,
      listenFor: listenFor,
      pauseFor: pauseFor,
      listenOptions: listenOptions,
      onStatus: onStatus,
      onError: onError,
    );
  }

  Future<bool> listen({
    required String owner,
    required stt.SpeechResultListener onResult,
    String? localeId,
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 2),
    stt.SpeechListenOptions? listenOptions,
    void Function(String)? onStatus,
    void Function(dynamic)? onError,
  }) async {
    final ready = await ensureInitialized(
      owner: owner,
      onStatus: onStatus,
      onError: onError,
    );
    if (!ready) return false;

    if (_speech.isListening && _activeOwner != owner) {
      await stop();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    _activeOwner = owner;
    if (onStatus != null) _onStatus = onStatus;
    if (onError != null) _onError = onError;

    try {
      await _speech.listen(
        onResult: onResult,
        localeId: localeId,
        listenFor: listenFor,
        pauseFor: pauseFor,
        listenOptions: listenOptions ??
            stt.SpeechListenOptions(
              partialResults: true,
              cancelOnError: false,
            ),
      );
      return true;
    } catch (e) {
      debugPrint('AppSpeechService listen error ($owner): $e');
      _activeOwner = null;
      return false;
    }
  }
}
