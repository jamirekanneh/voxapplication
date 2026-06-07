import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'app_speech_service.dart';
import 'read_aloud_ui.dart';
import 'reading_audio_session.dart';
import 'reading_sherpa_keyword_handler.dart';
import 'reading_voice_keyword.dart';
import 'sherpa_kws_model_manager.dart';
import 'sherpa_pcm_utils.dart';

/// On-device keyword spotting while TTS plays (Sherpa-ONNX — no API key).
class ReadAloudKwsService {
  ReadAloudKwsService._();
  static final ReadAloudKwsService instance = ReadAloudKwsService._();

  static bool _bindingsReady = false;

  final AudioRecorder _recorder = AudioRecorder();

  sherpa.KeywordSpotter? _spotter;
  sherpa.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _micSub;

  bool _sessionActive = false;
  bool _initializing = false;
  bool _suspended = false;
  bool _dispatching = false;

  Future<void> Function(ReadingVoiceKeyword keyword)? _onKeyword;
  VoidCallback? _onMicReady;
  VoidCallback? _onPotentialVoiceTrigger;
  VoidCallback? _onVoiceQuiet;

  bool _voiceEnergyActive = false;
  bool _keywordHandledSinceDuck = false;
  Timer? _voiceQuietTimer;

  static const double _voiceEnergyThreshold = 0.008;
  static const Duration _voiceQuietDelay = Duration(milliseconds: 1200);

  bool get isAvailable => _spotter != null;
  bool get isRunning => _sessionActive && !_suspended && _micSub != null;

  Future<bool> tryInitialize() async {
    if (_spotter != null) return true;
    if (_initializing) return false;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return false;

    _initializing = true;
    try {
      if (!_bindingsReady) {
        sherpa.initBindings();
        _bindingsReady = true;
      }

      final modelDir = await SherpaKwsModelManager.instance.ensureModelDir(
        onStatus: ReadAloudUi.showFeedback,
      );
      if (modelDir == null) return false;

      _spotter?.free();
      _spotter = await SherpaKwsModelManager.instance.createSpotter(modelDir);
      debugPrint('ReadAloudKwsService: keyword spotter ready');
      return _spotter != null;
    } catch (e) {
      debugPrint('ReadAloudKwsService init failed: $e');
      _spotter = null;
      return false;
    } finally {
      _initializing = false;
    }
  }

  Future<bool> start({
    required Future<void> Function(ReadingVoiceKeyword keyword) onKeyword,
    VoidCallback? onMicReady,
    VoidCallback? onPotentialVoiceTrigger,
    VoidCallback? onVoiceQuiet,
  }) async {
    if (!await tryInitialize() || _spotter == null) return false;
    if (_sessionActive && !_suspended && _micSub != null) return true;

    _onKeyword = onKeyword;
    _onMicReady = onMicReady;
    _onPotentialVoiceTrigger = onPotentialVoiceTrigger;
    _onVoiceQuiet = onVoiceQuiet;
    _sessionActive = true;
    _suspended = false;

    if (!await _ensureMicPermission()) return false;

    await AppSpeechService.instance.stop();
    await ReadingAudioSession.activateForHandsFreeReadAloud();

    _stream?.free();
    _stream = _spotter!.createStream();

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );

      _micSub = stream.listen(
        _onPcmChunk,
        onError: (e) => debugPrint('ReadAloudKwsService mic: $e'),
        cancelOnError: false,
      );

      _onMicReady?.call();
      debugPrint('ReadAloudKwsService: listening for keywords');
      return true;
    } catch (e) {
      debugPrint('ReadAloudKwsService start failed: $e');
      await _stopMic();
      return false;
    }
  }

  Future<void> stop() async {
    _sessionActive = false;
    _suspended = false;
    _onKeyword = null;
    _onMicReady = null;
    _onPotentialVoiceTrigger = null;
    _onVoiceQuiet = null;
    _voiceQuietTimer?.cancel();
    _voiceQuietTimer = null;
    await _stopMic();
    _stream?.free();
    _stream = null;
    _spotter?.free();
    _spotter = null;
  }

  Future<void> suspend() async {
    _suspended = true;
    _voiceQuietTimer?.cancel();
    _voiceQuietTimer = null;
    await _stopMic();
  }

  Future<bool> _ensureMicPermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (!status.isGranted) {
      ReadAloudUi.showFeedback(
        'Allow microphone access in Settings for voice controls',
      );
      return false;
    }
    return _recorder.hasPermission();
  }

  Future<void> _stopMic() async {
    await _micSub?.cancel();
    _micSub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  void _onPcmChunk(Uint8List bytes) {
    if (!_sessionActive || _suspended || _spotter == null || _stream == null) {
      return;
    }

    _trackVoiceEnergy(bytes);

    final samples = pcm16BytesToFloat32(bytes);
    _stream!.acceptWaveform(samples: samples, sampleRate: 16000);

    while (_spotter!.isReady(_stream!)) {
      _spotter!.decode(_stream!);
      final result = _spotter!.getResult(_stream!);
      final keyword = ReadingSherpaKeywordHandler.map(result.keyword);
      if (keyword == null) continue;

      debugPrint('ReadAloudKwsService heard ${result.keyword} → $keyword');
      _keywordHandledSinceDuck = true;
      _onVoiceQuiet?.call();
      _spotter!.reset(_stream!);
      unawaited(_dispatch(keyword));
      break;
    }
  }

  void _trackVoiceEnergy(Uint8List bytes) {
    final rms = pcm16Rms(bytes);
    if (rms < _voiceEnergyThreshold) return;

    final firstFrame = !_voiceEnergyActive;
    if (firstFrame) {
      _voiceEnergyActive = true;
      _keywordHandledSinceDuck = false;
    }
    // Re-apply duck on every loud frame — Android needs repeated setVolume calls.
    _onPotentialVoiceTrigger?.call();

    _voiceQuietTimer?.cancel();
    _voiceQuietTimer = Timer(_voiceQuietDelay, () {
      _voiceQuietTimer = null;
      _voiceEnergyActive = false;
      if (!_keywordHandledSinceDuck) {
        _onVoiceQuiet?.call();
      }
      _keywordHandledSinceDuck = false;
    });
  }

  Future<void> _dispatch(ReadingVoiceKeyword keyword) async {
    if (!_sessionActive || _dispatching) return;
    _dispatching = true;
    try {
      final handler = _onKeyword;
      if (handler != null) {
        await handler(keyword);
      }
    } finally {
      _dispatching = false;
    }
  }
}
