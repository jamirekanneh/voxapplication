import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Audio session for hands-free read-aloud voice commands while TTS is playing.
///
/// Uses play-and-record / voice-communication on Android with
/// [AndroidAudioFocusGainType.gainTransientMayDuck] so the mic and speaker
/// can share the audio hardware without one silencing the other.
class ReadingAudioSession {
  ReadingAudioSession._();

  static bool _configured = false;

  /// Mic-only session while read-aloud is paused (no TTS — full reliability on speaker or earphones).
  static Future<void> activateForPausedVoiceCommands() async {
    if (kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.mixWithOthers,
          avAudioSessionMode: AVAudioSessionMode.measurement,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: false,
        ),
      );
      await session.setActive(true);
      _configured = true;
    } catch (e) {
      debugPrint('ReadingAudioSession: paused voice configure failed: $e');
    }
  }

  /// Play-and-record routed to earphones (no forced speaker — best for hands-free).
  static Future<void> activateForHeadphoneReadAloud() async {
    if (kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.mixWithOthers,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: false,
        ),
      );
      await session.setActive(true);
      _configured = true;
    } catch (e) {
      debugPrint('ReadingAudioSession: headphone configure failed: $e');
    }
  }

  /// Play-and-record + voice communication (hands-free read-aloud on phone speaker).
  static Future<void> activateForHandsFreeReadAloud() async {
    if (kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.defaultToSpeaker |
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.mixWithOthers |
              AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: false,
        ),
      );
      await session.setActive(true);
      _configured = true;
    } catch (e) {
      debugPrint('ReadingAudioSession: hands-free configure failed: $e');
    }
  }

  /// Call before starting continuous STT during read-aloud playback.
  static Future<void> activateForVoiceCommands() async {
    await activateForHandsFreeReadAloud();
  }

  /// Playback-only session so TTS can take the speaker (resume / play).
  static Future<void> activateForTtsOutput() async {
    if (kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        ),
      );
      await session.setActive(true);
      _configured = true;
    } catch (e) {
      debugPrint('ReadingAudioSession: TTS output configure failed: $e');
    }
  }

  /// Release the voice-command session when read-aloud ends.
  static Future<void> deactivate() async {
    if (!_configured) return;
    _configured = false;
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (e) {
      debugPrint('ReadingAudioSession: deactivate failed: $e');
    }
  }
}
