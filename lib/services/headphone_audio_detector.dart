import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Detects wired / Bluetooth earphones so read-aloud voice control can skip
/// speaker-echo ducking and use full TTS volume.
class HeadphoneAudioDetector {
  HeadphoneAudioDetector._();
  static final HeadphoneAudioDetector instance = HeadphoneAudioDetector._();

  bool _headphonesConnected = false;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesSub;

  bool get isHeadphonesConnected => _headphonesConnected;

  Future<void> init() async {
    if (kIsWeb) return;
    await refresh();
    _devicesSub?.cancel();
    try {
      final session = await AudioSession.instance;
      _devicesSub = session.devicesChangedEventStream.listen((_) {
        unawaited(refresh());
      });
    } catch (e) {
      debugPrint('HeadphoneAudioDetector init: $e');
    }
  }

  Future<void> dispose() async {
    await _devicesSub?.cancel();
    _devicesSub = null;
  }

  Future<bool> refresh() async {
    if (kIsWeb) {
      _headphonesConnected = false;
      return false;
    }
    try {
      final session = await AudioSession.instance;
      final outputs = await session.getDevices(
        includeInputs: false,
        includeOutputs: true,
      );
      final connected = outputs.any(
        (d) => d.isOutput && _isHeadphoneType(d.type),
      );
      if (connected != _headphonesConnected) {
        debugPrint(
          'HeadphoneAudioDetector: ${connected ? "earphones on" : "phone speaker"}',
        );
      }
      _headphonesConnected = connected;
      return connected;
    } catch (e) {
      debugPrint('HeadphoneAudioDetector refresh: $e');
      return _headphonesConnected;
    }
  }

  static bool _isHeadphoneType(AudioDeviceType type) {
    switch (type) {
      case AudioDeviceType.wiredHeadphones:
      case AudioDeviceType.wiredHeadset:
      case AudioDeviceType.bluetoothA2dp:
      case AudioDeviceType.bluetoothSco:
      case AudioDeviceType.bluetoothLe:
      case AudioDeviceType.usbAudio:
        return true;
      default:
        return false;
    }
  }
}
