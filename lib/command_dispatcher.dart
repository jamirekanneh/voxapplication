import 'package:flutter/material.dart';
import 'ai_service.dart';
import 'config/secrets.dart';
import 'analytics_service.dart';
import 'custom_commands_provider.dart';
import 'language_provider.dart';
import 'navigation_keys.dart';
import 'services/mic_coordinator.dart';
import 'services/assistant_voice_phrases.dart';
import 'services/document_language_service.dart';
import 'services/reading_voice_commands.dart';
import 'services/reading_voice_keyword.dart';
import 'tts_service.dart';
import 'voice_assistant_intent.dart';

// ─────────────────────────────────────────────
//  VOICE FEEDBACK STRINGS (all app languages)
// ─────────────────────────────────────────────
const Map<String, Map<String, String>> _feedback = {
  'English': {
    'navigateHome': 'Going to Home',
    'navigateNotes': 'Opening Notes',
    'navigateMenu': 'Opening Menu',
    'navigateDictionary': 'Opening Dictionary',
    'ttsPlay': 'Resuming',
    'ttsPause': 'Paused',
    'ttsStop': 'Stopped',
    'ttsSpeedUp': 'Speeding up',
    'ttsSlowDown': 'Slowing down',
    'searchNotes': 'Searching notes',
    'openNote': 'Opening note',
    'searchLibrary': 'Searching library',
    'openAssessments': 'Opening Saved Docs',
    'assistantMuted': 'Voice assistant muted',
    'noMatch': 'Command not recognized',
    'navigateProfile': 'Opening Profile',
    'navigateCustomCommands': 'Opening Personalized Commands',
    'navigateAbout': 'Opening About Us',
    'navigateStatistics': 'Opening Statistics',
    'navigateContact': 'Opening Contact Us',
    'navigateFaqs': 'Opening FAQs',
    'navigateRecommendations': 'Opening Recommendations',
    'navigateRecycleBin': 'Opening Recycle Bin',
    'navigateHistory': 'Opening History',
    'openLanguagePicker': 'Opening language selection',
  },
  'Spanish': {
    'navigateHome': 'Yendo al inicio',
    'navigateNotes': 'Abriendo notas',
    'navigateMenu': 'Abriendo menú',
    'navigateDictionary': 'Abriendo diccionario',
    'ttsPlay': 'Reanudando',
    'ttsPause': 'Pausado',
    'ttsStop': 'Detenido',
    'ttsSpeedUp': 'Acelerando',
    'ttsSlowDown': 'Ralentizando',
    'searchNotes': 'Buscando notas',
    'openNote': 'Abriendo nota',
    'searchLibrary': 'Buscando en la biblioteca',
    'openAssessments': 'Abriendo evaluaciones guardadas',
    'assistantMuted': 'Asistente de voz desactivado',
    'noMatch': 'Comando no reconocido',
  },
  'French': {
    'navigateHome': 'Retour à l\'accueil',
    'navigateNotes': 'Ouverture des notes',
    'navigateMenu': 'Ouverture du menu',
    'navigateDictionary': 'Ouverture du dictionnaire',
    'ttsPlay': 'Reprise',
    'ttsPause': 'En pause',
    'ttsStop': 'Arrêté',
    'ttsSpeedUp': 'Accélération',
    'ttsSlowDown': 'Ralentissement',
    'searchNotes': 'Recherche de notes',
    'openNote': 'Ouverture de la note',
    'searchLibrary': 'Recherche dans la bibliothèque',
    'openAssessments': 'Ouverture des évaluations enregistrées',
    'assistantMuted': 'Assistant vocal désactivé',
    'noMatch': 'Commande non reconnue',
  },
  'Arabic': {
    'navigateHome': 'الذهاب إلى الرئيسية',
    'navigateNotes': 'فتح الملاحظات',
    'navigateMenu': 'فتح القائمة',
    'navigateDictionary': 'فتح القاموس',
    'ttsPlay': 'استئناف',
    'ttsPause': 'إيقاف مؤقت',
    'ttsStop': 'إيقاف',
    'ttsSpeedUp': 'تسريع',
    'ttsSlowDown': 'تبطيء',
    'searchNotes': 'البحث في الملاحظات',
    'openNote': 'فتح الملاحظة',
    'searchLibrary': 'البحث في المكتبة',
    'openAssessments': 'فتح التقييمات المحفوظة',
    'assistantMuted': 'تم إيقاف المساعد الصوتي',
    'noMatch': 'الأمر غير معروف',
  },
  'Turkish': {
    'navigateHome': 'Ana sayfaya gidiliyor',
    'navigateNotes': 'Notlar açılıyor',
    'navigateMenu': 'Menü açılıyor',
    'navigateDictionary': 'Sözlük açılıyor',
    'ttsPlay': 'Devam ediliyor',
    'ttsPause': 'Duraklatıldı',
    'ttsStop': 'Durduruldu',
    'ttsSpeedUp': 'Hızlandırılıyor',
    'ttsSlowDown': 'Yavaşlatılıyor',
    'searchNotes': 'Notlarda aranıyor',
    'openNote': 'Not açılıyor',
    'searchLibrary': 'Kütüphanede aranıyor',
    'openAssessments': 'Kayıtlı değerlendirmeler açılıyor',
    'assistantMuted': 'Sesli asistan kapatıldı',
    'noMatch': 'Komut tanınmadı',
  },
  'Chinese': {
    'navigateHome': '返回主页',
    'navigateNotes': '打开笔记',
    'navigateMenu': '打开菜单',
    'navigateDictionary': '打开词典',
    'ttsPlay': '继续播放',
    'ttsPause': '已暂停',
    'ttsStop': '已停止',
    'ttsSpeedUp': '加速',
    'ttsSlowDown': '减速',
    'searchNotes': '搜索笔记',
    'openNote': '打开笔记',
    'searchLibrary': '搜索图书馆',
    'openAssessments': '打开保存的评估',
    'assistantMuted': '语音助手已关闭',
    'noMatch': '未识别命令',
  },
};

String _getFeedback(String language, String key) {
  final lang = _feedback.containsKey(language) ? language : 'English';
  return _feedback[lang]?[key] ?? _feedback['English']![key]!;
}

String _responseLanguage(String spokenText, String appLanguage) {
  return DocumentLanguageService.detectSpokenLanguageName(
    spokenText,
    fallback: appLanguage,
  );
}

String _ttsLocaleForLanguage(String language) =>
    DocumentLanguageService.ttsLocaleForLanguage(language);

// ─────────────────────────────────────────────
//  DISPATCHER
// ─────────────────────────────────────────────
class CommandDispatcher {
  static CommandActionType? _mapNlAction(VoiceAssistantAction a) {
    switch (a) {
      case VoiceAssistantAction.navigateHome:
        return CommandActionType.navigateHome;
      case VoiceAssistantAction.navigateNotes:
        return CommandActionType.navigateNotes;
      case VoiceAssistantAction.navigateMenu:
        return CommandActionType.navigateMenu;
      case VoiceAssistantAction.navigateDictionary:
        return CommandActionType.navigateDictionary;
      case VoiceAssistantAction.searchLibrary:
        return CommandActionType.searchLibrary;
      case VoiceAssistantAction.searchNotes:
        return CommandActionType.searchNotes;
      case VoiceAssistantAction.openNote:
        return CommandActionType.openNote;
      case VoiceAssistantAction.openAssessments:
        return CommandActionType.openAssessments;
      case VoiceAssistantAction.readingPlay:
        return CommandActionType.ttsPlay;
      case VoiceAssistantAction.readingPause:
        return CommandActionType.ttsPause;
      case VoiceAssistantAction.readingStop:
        return CommandActionType.ttsStop;
      case VoiceAssistantAction.readingFaster:
        return CommandActionType.ttsSpeedUp;
      case VoiceAssistantAction.readingSlower:
        return CommandActionType.ttsSlowDown;
      case VoiceAssistantAction.navigateProfile:
        return CommandActionType.navigateProfile;
      case VoiceAssistantAction.navigateCustomCommands:
        return CommandActionType.navigateCustomCommands;
      case VoiceAssistantAction.navigateAbout:
        return CommandActionType.navigateAbout;
      case VoiceAssistantAction.navigateStatistics:
        return CommandActionType.navigateStatistics;
      case VoiceAssistantAction.navigateContact:
        return CommandActionType.navigateContact;
      case VoiceAssistantAction.navigateFaqs:
        return CommandActionType.navigateFaqs;
      case VoiceAssistantAction.navigateRecommendations:
        return CommandActionType.navigateRecommendations;
      case VoiceAssistantAction.navigateRecycleBin:
        return CommandActionType.navigateRecycleBin;
      case VoiceAssistantAction.navigateHistory:
        return CommandActionType.navigateHistory;
      case VoiceAssistantAction.openLanguagePicker:
        return CommandActionType.openLanguagePicker;
      case VoiceAssistantAction.assistantOff:
        return null;
      case VoiceAssistantAction.customCommand:
        return CommandActionType.customCommand;
      case VoiceAssistantAction.none:
        return CommandActionType.none;
      case VoiceAssistantAction.unknown:
        return null;
    }
  }

  static Future<bool> _dispatchNlIntent({
    required BuildContext context,
    required VoiceAssistantInterpretation nl,
    required CustomCommandsProvider commandsProvider,
    required TtsService ttsService,
    required String responseLanguage,
    required String responseLocale,
  }) async {
    switch (nl.action) {
      case VoiceAssistantAction.unknown:
        return false;

      case VoiceAssistantAction.none:
        if (!context.mounted) return true;
        if (commandsProvider.voiceFeedbackEnabled) {
          final r = nl.replyEnglish?.trim();
          if (r != null && r.isNotEmpty) {
            ttsService.speakBrief(r, responseLocale);
          } else {
            ttsService.speakBrief(
              _getFeedback(responseLanguage, 'noMatch'),
              responseLocale,
            );
          }
        }
        return true;

      case VoiceAssistantAction.assistantOff:
        await commandsProvider.setAssistantMode(false);
        MicCoordinator.instance.setAssistantMicActive(false);
        if (!context.mounted) return true;
        if (commandsProvider.voiceFeedbackEnabled) {
          await ttsService.speakBrief(
            _getFeedback(responseLanguage, 'assistantMuted'),
            responseLocale,
          );
        }
        return true;

      case VoiceAssistantAction.customCommand:
        final cId = nl.customCommandId;
        debugPrint('DISPATCH: Custom command selected: $cId');
        if (cId == null) return false;
        try {
          final customCmd = commandsProvider.commands.firstWhere((c) => c.id == cId);
          debugPrint('DISPATCH: Executing custom command phrase: "${customCmd.phrase}"');
          if (!context.mounted) return false;
          
          // Siri-style: Navigation happens FIRST
          if (customCmd.action == CommandActionType.macroSequence &&
              customCmd.parameter != null &&
              customCmd.parameter!.trim().isNotEmpty) {
            final steps = customCmd.parameter!
                .split(RegExp(r'[\r\n;]+'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            for (final step in steps) {
              final subCommand = commandsProvider.match(step);
              if (subCommand != null) {
                _execute(context, subCommand, ttsService, responseLocale);
              }
            }
          } else {
            _execute(context, customCmd, ttsService, responseLocale);
          }

          if (commandsProvider.voiceFeedbackEnabled) {
            final feedbackText =
                _getFeedback(responseLanguage, customCmd.action.name);
            ttsService.speakBrief(feedbackText, responseLocale);
          }
          
          return true;
        } catch (_) {
          return false;
        }

      default:
        final mapped = _mapNlAction(nl.action);
        if (mapped == null || !context.mounted) return false;

        AnalyticsService.instance.recordVoiceCommand(mapped.displayName);

        final cmd = CustomCommand(
          id: '_nl_${nl.action.name}',
          phrase: '__nl__',
          action: mapped,
          parameter: nl.query ?? '',
        );

        if (!context.mounted) return false;

        // Siri-style: Action happens FIRST
        _execute(context, cmd, ttsService, responseLocale);

        if (commandsProvider.voiceFeedbackEnabled) {
          var feedbackText =
              _getFeedback(responseLanguage, cmd.action.name);
          final p = (nl.query ?? '').trim();
          if (p.isNotEmpty &&
              (mapped == CommandActionType.searchNotes ||
                  mapped == CommandActionType.openNote ||
                  mapped == CommandActionType.searchLibrary)) {
            feedbackText += ': $p';
          }
          ttsService.speakBrief(feedbackText, responseLocale);
        }

        return true;
    }
  }

  static Future<bool> dispatch({
    required BuildContext context,
    required String spokenText,
    required CustomCommandsProvider commandsProvider,
    required TtsService ttsService,
    required LanguageProvider langProvider,
  }) async {
    final appLanguage = langProvider.selectedLanguage;
    final responseLanguage = _responseLanguage(spokenText, appLanguage);
    final responseLocale = _ttsLocaleForLanguage(responseLanguage);

    // While a document is being read aloud, reading commands take priority.
    final readingResult = await ReadingVoiceCommands.tryDuringPlayback(
      spoken: spokenText,
      tts: ttsService,
      locale: responseLocale,
    );
    if (readingResult.handled) {
      if (!context.mounted) return true;
      if (readingResult.dictionaryQuery != null) {
        globalNavigatorKey.currentState?.pushNamed(
          '/dictionary',
          arguments: {'searchQuery': readingResult.dictionaryQuery},
        );
      } else if (readingResult.closeReader) {
        final nav = globalNavigatorKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        }
      }
      if (readingResult.feedback.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(readingResult.feedback),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return true;
    }

    VoiceAssistantInterpretation? interpreted;
    debugPrint('DISPATCH START: "$spokenText"');
    
    // SPEED FIX: If the user hasn't set their OpenRouter key, don't even TRY the AI.
    // This removes the 10-20 second "slow" feeling of a failing request.
    final isPlaceholder = kOpenRouterKey.isEmpty ||
        kOpenRouterKey.toLowerCase().contains('your_') ||
        kOpenRouterKey.toLowerCase().contains('api_key');
                          
    if (isPlaceholder) {
      debugPrint(
        'DISPATCH: OpenRouter key missing or placeholder, skipping AI phase.',
      );
    } else {
      try {
        interpreted = await AiService.interpretVoiceAssistant(
          transcript: spokenText,
          customCommands: commandsProvider.enabledCommands,
          fallbackLanguage: appLanguage,
        );
        debugPrint('AI INTERPRETATION: ${interpreted?.action}');
      } catch (e) {
        debugPrint('AI SERVICE ERROR: $e');
        interpreted = null;
      }
    }

    if (!context.mounted) return false;

    if (interpreted != null) {
      final handled = await _dispatchNlIntent(
        context: context,
        nl: interpreted,
        commandsProvider: commandsProvider,
        ttsService: ttsService,
        responseLanguage: responseLanguage,
        responseLocale: responseLocale,
      );
      if (handled) {
        debugPrint('DISPATCH: Handled by AI Intent');
        return true;
      }
    }

    debugPrint('DISPATCH: Falling back to local matcher (lang=$responseLanguage)');

    final localizedCmd = AssistantVoicePhrases.matchSpoken(
      spokenText,
      appLanguage: appLanguage,
    );
    if (localizedCmd != null) {
      debugPrint('DISPATCH: Localized phrase → ${localizedCmd.action.name}');
      AnalyticsService.instance.recordVoiceCommand(
        localizedCmd.action.displayName,
      );
      await _execute(context, localizedCmd, ttsService, responseLocale);
      if (commandsProvider.voiceFeedbackEnabled) {
        var feedbackText =
            _getFeedback(responseLanguage, localizedCmd.action.name);
        final p = localizedCmd.parameter?.trim();
        if (p != null && p.isNotEmpty) feedbackText += ': $p';
        ttsService.speakBrief(feedbackText, responseLocale);
      }
      return true;
    }

    if (ttsService.isReadingSession &&
        (ttsService.isPlaying || ttsService.userPaused)) {
      final seek = ReadingVoiceKeywordSpotter.spotSeekOnly(
        spokenText,
        commandLanguage: responseLanguage,
      );
      if (seek == ReadingVoiceKeyword.forward) {
        await ttsService.seekForward(10, responseLocale);
        return true;
      }
      if (seek == ReadingVoiceKeyword.backward) {
        await ttsService.seekBackward(10, responseLocale);
        return true;
      }
    }

    final matched = commandsProvider.match(
      spokenText,
      language: responseLanguage,
      appLanguage: appLanguage,
    );

    if (matched == null) {
      AnalyticsService.instance.recordUnmatchedCommand(spokenText);
      if (commandsProvider.voiceFeedbackEnabled) {
        ttsService.speakBrief(
          _getFeedback(responseLanguage, 'noMatch'),
          responseLocale,
        );
      }
      return false;
    }

    // Track voice command usage
    AnalyticsService.instance.recordVoiceCommand(matched.action.displayName);

    // Siri-style: Navigation happens FIRST
    if (matched.action == CommandActionType.macroSequence &&
        matched.parameter != null &&
        matched.parameter!.trim().isNotEmpty) {
      final steps = matched.parameter!
          .split(RegExp(r'[\r\n;]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      for (final step in steps) {
        final subCommand = commandsProvider.match(step);
        if (subCommand != null) {
          _execute(context, subCommand, ttsService, responseLocale);
        } else if (commandsProvider.voiceFeedbackEnabled) {
          ttsService.speakBrief('Macro step not found: $step', responseLocale);
        }
      }
    } else {
      _execute(context, matched, ttsService, responseLocale);
    }

    if (commandsProvider.voiceFeedbackEnabled) {
      String feedbackText = _getFeedback(responseLanguage, matched.action.name);
      if (matched.parameter != null && matched.parameter!.isNotEmpty) {
        feedbackText += ': ${matched.parameter}';
      }
      ttsService.speakBrief(feedbackText, responseLocale);
    }

    return true;
  }

  static Future<void> _execute(
    BuildContext context,
    CustomCommand command,
    TtsService ttsService,
    String locale,
  ) async {
    debugPrint('EXECUTING ACTION: ${command.action}');
    switch (command.action) {
      // FIX: use globalNavigatorKey since this context might be above the navigator
      case CommandActionType.navigateHome:
        debugPrint('NAVIGATING: /home (NavState: ${globalNavigatorKey.currentState != null})');
        globalNavigatorKey.currentState?.pushNamed('/home');
        break;
      case CommandActionType.navigateNotes:
        debugPrint('NAVIGATING: /notes (NavState: ${globalNavigatorKey.currentState != null})');
        globalNavigatorKey.currentState?.pushNamed('/notes');
        break;
      case CommandActionType.navigateMenu:
        debugPrint('NAVIGATING: /menu (NavState: ${globalNavigatorKey.currentState != null})');
        globalNavigatorKey.currentState?.pushNamed('/menu');
        break;
      case CommandActionType.navigateDictionary:
        debugPrint('NAVIGATING: /dictionary (NavState: ${globalNavigatorKey.currentState != null})');
        final query = (command.parameter ?? '').trim();
        globalNavigatorKey.currentState?.pushNamed(
          '/dictionary',
          arguments: query.isEmpty ? null : {'searchQuery': query},
        );
        break;
      case CommandActionType.ttsPlay:
        if (ttsService.isReadingSession && ttsService.userPaused) {
          await ttsService.resumeReading(locale);
        }
        break;
      case CommandActionType.ttsPause:
        if (ttsService.isReadingSession &&
            (ttsService.isPlaying || !ttsService.userPaused)) {
          await ttsService.pauseReading(locale);
        }
        break;
      case CommandActionType.ttsStop:
        await ttsService.stop();
        break;
      case CommandActionType.ttsSpeedUp:
        await ttsService.setRate(ttsService.speechRate + 0.2, locale);
        break;
      case CommandActionType.ttsSlowDown:
        await ttsService.setRate(ttsService.speechRate - 0.2, locale);
        break;
      case CommandActionType.searchNotes:
        globalNavigatorKey.currentState!.pushNamed(
          '/notes',
          arguments: {'searchQuery': command.parameter ?? ''},
        );
        break;
      case CommandActionType.openNote:
        globalNavigatorKey.currentState!.pushNamed(
          '/notes',
          arguments: {'openNote': command.parameter ?? ''},
        );
        break;
      case CommandActionType.searchLibrary:
        globalNavigatorKey.currentState!.pushNamed(
          '/home',
          arguments: {'searchQuery': command.parameter ?? ''},
        );
        break;
      case CommandActionType.openAssessments:
        globalNavigatorKey.currentState!.pushNamed('/saved_docs');
        break;
      case CommandActionType.navigateProfile:
        globalNavigatorKey.currentState!.pushNamed('/profile');
        break;
      case CommandActionType.navigateCustomCommands:
        globalNavigatorKey.currentState!.pushNamed('/custom_commands');
        break;
      case CommandActionType.navigateAbout:
        globalNavigatorKey.currentState!.pushNamed('/about');
        break;
      case CommandActionType.navigateStatistics:
        globalNavigatorKey.currentState!.pushNamed('/statistics');
        break;
      case CommandActionType.navigateContact:
        globalNavigatorKey.currentState!.pushNamed('/contact');
        break;
      case CommandActionType.navigateFaqs:
        globalNavigatorKey.currentState!.pushNamed('/faqs');
        break;
      case CommandActionType.navigateRecommendations:
        globalNavigatorKey.currentState!.pushNamed('/recommendations');
        break;
      case CommandActionType.navigateRecycleBin:
        globalNavigatorKey.currentState!.pushNamed('/recycle_bin');
        break;
      case CommandActionType.navigateHistory:
        globalNavigatorKey.currentState!.pushNamed('/history');
        break;
      case CommandActionType.openLanguagePicker:
        // For now, jump to menu page where the picker button is prominent,
        // or we could implement a global picker show here.
        globalNavigatorKey.currentState!.pushNamed('/menu');
        break;
      case CommandActionType.macroSequence:
        // Macro logic is handled in dispatch; no direct action here.
        break;
      case CommandActionType.customCommand:
        // Base case for custom actions; primarily handled in dispatch.
        break;
      case CommandActionType.none:
        // Explicitly do nothing.
        break;
    }
  }
}
