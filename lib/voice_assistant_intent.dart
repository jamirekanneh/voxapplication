// Structured output from AiService.interpretVoiceAssistant for navigation / actions.

enum VoiceAssistantAction {
  unknown,
  /// Nothing to do — allow phrase fallback unless [replyEnglish] speaks a short dismissal.
  none,
  navigateHome,
  navigateNotes,
  navigateMenu,
  navigateDictionary,
  searchLibrary,
  searchNotes,
  openNote,
  openAssessments,
  readingPlay,
  readingPause,
  readingStop,
  readingFaster,
  readingSlower,
  assistantOff,
}

VoiceAssistantAction voiceAssistantActionFromApi(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'none':
    case 'noop':
      return VoiceAssistantAction.none;
    case 'navigate_home':
    case 'go_home':
    case 'home':
      return VoiceAssistantAction.navigateHome;
    case 'navigate_notes':
    case 'notes':
      return VoiceAssistantAction.navigateNotes;
    case 'navigate_menu':
    case 'menu':
      return VoiceAssistantAction.navigateMenu;
    case 'navigate_dictionary':
    case 'dictionary':
      return VoiceAssistantAction.navigateDictionary;
    case 'search_library':
    case 'library_search':
      return VoiceAssistantAction.searchLibrary;
    case 'search_notes':
      return VoiceAssistantAction.searchNotes;
    case 'open_note':
      return VoiceAssistantAction.openNote;
    case 'open_assessments':
    case 'open_saved_qa':
    case 'saved_qa':
    case 'saved_assessments':
      return VoiceAssistantAction.openAssessments;
    case 'reading_play':
    case 'tts_play':
      return VoiceAssistantAction.readingPlay;
    case 'reading_pause':
    case 'tts_pause':
      return VoiceAssistantAction.readingPause;
    case 'reading_stop':
    case 'tts_stop':
      return VoiceAssistantAction.readingStop;
    case 'reading_faster':
    case 'tts_speed_up':
      return VoiceAssistantAction.readingFaster;
    case 'reading_slower':
    case 'tts_slow_down':
      return VoiceAssistantAction.readingSlower;
    case 'assistant_off':
    case 'stop_assistant':
      return VoiceAssistantAction.assistantOff;
    default:
      return VoiceAssistantAction.unknown;
  }
}

class VoiceAssistantInterpretation {
  final VoiceAssistantAction action;
  final String? query;
  final String? replyEnglish;

  const VoiceAssistantInterpretation({
    required this.action,
    this.query,
    this.replyEnglish,
  });

  static VoiceAssistantInterpretation tryParse(Map<String, dynamic> decoded) {
    final a = decoded['action'];
    final action =
        voiceAssistantActionFromApi(a is String ? a : a?.toString());
    final q = decoded['query'];
    String? queryStr;
    if (q != null && q.toString().trim().isNotEmpty) {
      queryStr = q.toString().trim();
    }
    final r = decoded['reply'];
    String? reply;
    if (r != null && r.toString().trim().isNotEmpty) {
      reply = r.toString().trim();
    }
    return VoiceAssistantInterpretation(
      action: action,
      query: queryStr,
      replyEnglish: reply,
    );
  }
}
