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
  customCommand,
  navigateProfile,
  navigateCustomCommands,
  navigateAbout,
  navigateStatistics,
  navigateContact,
  navigateFaqs,
  navigateRecommendations,
  navigateRecycleBin,
  navigateHistory,
  openLanguagePicker,
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
    case 'custom_command':
      return VoiceAssistantAction.customCommand;
    case 'navigate_profile':
    case 'profile':
    case 'user_profile':
      return VoiceAssistantAction.navigateProfile;
    case 'navigate_custom_commands':
    case 'custom_commands':
    case 'personalized_commands':
      return VoiceAssistantAction.navigateCustomCommands;
    case 'navigate_about':
    case 'about':
    case 'about_us':
      return VoiceAssistantAction.navigateAbout;
    case 'navigate_statistics':
    case 'statistics':
    case 'stats':
    case 'usage':
      return VoiceAssistantAction.navigateStatistics;
    case 'navigate_contact':
    case 'contact':
    case 'contact_us':
    case 'email_us':
      return VoiceAssistantAction.navigateContact;
    case 'navigate_faqs':
    case 'faqs':
    case 'questions':
    case 'ask_questions':
      return VoiceAssistantAction.navigateFaqs;
    case 'navigate_recommendations':
    case 'recommendations':
    case 'suggested':
      return VoiceAssistantAction.navigateRecommendations;
    case 'navigate_recycle_bin':
    case 'recycle_bin':
    case 'trash':
    case 'deleted':
      return VoiceAssistantAction.navigateRecycleBin;
    case 'navigate_history':
    case 'history':
    case 'recent':
      return VoiceAssistantAction.navigateHistory;
    case 'open_languages':
    case 'languages':
    case 'select_language':
    case 'language_picker':
      return VoiceAssistantAction.openLanguagePicker;
    default:
      return VoiceAssistantAction.unknown;
  }
}

class VoiceAssistantInterpretation {
  final VoiceAssistantAction action;
  final String? query;
  final String? replyEnglish;
  final String? customCommandId;

  const VoiceAssistantInterpretation({
    required this.action,
    this.query,
    this.replyEnglish,
    this.customCommandId,
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
    
    final cid = decoded['customCommandId'] ?? decoded['custom_command_id'];
    String? cIdStr;
    if (cid != null && cid.toString().trim().isNotEmpty) {
      cIdStr = cid.toString().trim();
    }
    
    return VoiceAssistantInterpretation(
      action: action,
      query: queryStr,
      replyEnglish: reply,
      customCommandId: cIdStr,
    );
  }
}
