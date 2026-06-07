import 'reading_voice_keyword.dart';

/// Maps Sherpa KWS keyword tags (@PAUSE, @PLAY, …) to read-aloud commands.
class ReadingSherpaKeywordHandler {
  ReadingSherpaKeywordHandler._();

  static ReadingVoiceKeyword? map(String detected) {
    final tag = detected.trim().toUpperCase();
    if (tag.isEmpty) return null;

    switch (tag) {
      case 'PAUSE':
        return ReadingVoiceKeyword.pause;
      case 'PLAY':
      case 'CONTINUE':
      case 'RESUME':
        return ReadingVoiceKeyword.play;
      case 'STOP':
        return ReadingVoiceKeyword.stop;
      case 'FORWARD':
      case 'SKIP':
        return ReadingVoiceKeyword.forward;
      case 'BACKWARD':
      case 'BACK':
        return ReadingVoiceKeyword.backward;
      default:
        return null;
    }
  }
}
