import 'package:flutter/foundation.dart';

import '../tts_service.dart';
import 'reading_playback_state.dart';
import 'reading_voice_commands.dart';
import 'reading_voice_keyword.dart';

/// Result of dispatching a voice keyword to the read-aloud controller.
class ReadingVoiceDispatchResult {
  final bool handled;
  final bool closeReader;

  const ReadingVoiceDispatchResult({
    required this.handled,
    this.closeReader = false,
  });

  static const none = ReadingVoiceDispatchResult(handled: false);
}

/// Event-driven controller: keyword → interrupt TTS → update playback state.
class ReadingVoiceController {
  ReadingVoiceController._();
  static final ReadingVoiceController instance = ReadingVoiceController._();

  DateTime? _lastCommandAt;
  ReadingVoiceKeyword? _lastKeyword;

  bool _debounce(ReadingVoiceKeyword keyword) {
    final now = DateTime.now();
    if (_lastKeyword == keyword &&
        _lastCommandAt != null &&
        now.difference(_lastCommandAt!).inMilliseconds < 700) {
      return true;
    }
    _lastKeyword = keyword;
    _lastCommandAt = now;
    return false;
  }

  /// Handle a spotted keyword. Returns dispatch result.
  Future<ReadingVoiceDispatchResult> dispatch({
    required ReadingVoiceKeyword keyword,
    required TtsService tts,
    required String locale,
  }) async {
    if (!tts.isReadingSession) return ReadingVoiceDispatchResult.none;
    if (_debounce(keyword)) {
      return const ReadingVoiceDispatchResult(handled: true);
    }

    final state = tts.playbackState;
    debugPrint('ReadingVoiceController: $keyword @ $state');

    switch (keyword) {
      case ReadingVoiceKeyword.stop:
        await tts.stop();
        return const ReadingVoiceDispatchResult(
          handled: true,
          closeReader: true,
        );

      case ReadingVoiceKeyword.pause:
        if (state == ReadingPlaybackState.playing && !tts.userPaused) {
          await tts.pauseReading(locale);
        }
        return const ReadingVoiceDispatchResult(handled: true);

      case ReadingVoiceKeyword.play:
        if (state == ReadingPlaybackState.paused) {
          await tts.resumeReading(locale);
        }
        return const ReadingVoiceDispatchResult(handled: true);

      case ReadingVoiceKeyword.forward:
        await tts.skipToAdjacentSentence(1, locale);
        return const ReadingVoiceDispatchResult(handled: true);

      case ReadingVoiceKeyword.backward:
        await tts.skipToAdjacentSentence(-1, locale);
        return const ReadingVoiceDispatchResult(handled: true);

      case ReadingVoiceKeyword.highlight:
        ReadingVoiceCommands.onHighlightSentence?.call(tts);
        return const ReadingVoiceDispatchResult(handled: true);
    }
  }
}
