import '../tts_service.dart';

/// Read-aloud playback states for the voice-control state machine.
enum ReadingPlaybackState {
  idle,
  playing,
  paused,
}

extension TtsPlaybackState on TtsService {
  ReadingPlaybackState get playbackState {
    if (!isReadingSession) return ReadingPlaybackState.idle;
    if (isPlaying) return ReadingPlaybackState.playing;
    if (userPaused) return ReadingPlaybackState.paused;
    return ReadingPlaybackState.idle;
  }
}
