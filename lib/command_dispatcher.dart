import 'package:flutter/material.dart';
import 'ai_service.dart';
import 'config/secrets.dart';
import 'analytics_service.dart';
import 'custom_commands_provider.dart';
import 'language_provider.dart';
import 'main.dart';
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
    'openAssessments': 'Opening saved Q&A',
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
    required LanguageProvider langProvider,
  }) async {
    final locale = langProvider.currentLocale;
    final language = langProvider.selectedLanguage;

    switch (nl.action) {
      case VoiceAssistantAction.unknown:
        return false;

      case VoiceAssistantAction.none:
        if (!context.mounted) return true;
        if (commandsProvider.voiceFeedbackEnabled) {
          final r = nl.replyEnglish?.trim();
          if (r != null && r.isNotEmpty) {
            ttsService.play('', r, locale);
          } else {
            ttsService.play('', _getFeedback(language, 'noMatch'), locale);
          }
        }
        return true;

      case VoiceAssistantAction.assistantOff:
        await commandsProvider.setAssistantMode(false);
        if (!context.mounted) return true;
        if (commandsProvider.voiceFeedbackEnabled) {
          final r = nl.replyEnglish?.trim();
          await ttsService.play(
              '',
              (r != null && r.isNotEmpty)
                  ? r
                  : _getFeedback(language, 'assistantMuted'),
              locale);
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
                _execute(context, subCommand, ttsService, locale);
              }
            }
          } else {
            _execute(context, customCmd, ttsService, locale);
          }

          if (commandsProvider.voiceFeedbackEnabled) {
            String feedbackText = (nl.replyEnglish != null && nl.replyEnglish!.trim().isNotEmpty)
                ? nl.replyEnglish!.trim()
                : _getFeedback(language, customCmd.action.name);
            ttsService.play('', feedbackText, locale);
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
        _execute(context, cmd, ttsService, locale);

        if (commandsProvider.voiceFeedbackEnabled) {
          var feedbackText =
              (nl.replyEnglish != null && nl.replyEnglish!.trim().isNotEmpty)
                  ? nl.replyEnglish!.trim()
                  : _getFeedback(language, cmd.action.name);
          final p = (nl.query ?? '').trim();
          if (p.isNotEmpty &&
              (mapped == CommandActionType.searchNotes ||
                  mapped == CommandActionType.openNote ||
                  mapped == CommandActionType.searchLibrary)) {
            feedbackText += ': $p';
          }
          ttsService.play('', feedbackText, locale);
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
    VoiceAssistantInterpretation? interpreted;
    debugPrint('DISPATCH START: "$spokenText"');
    
    // SPEED FIX: If the user hasn't set their Groq key, don't even TRY the AI.
    // This removes the 10-20 second "slow" feeling of a failing request.
    final isPlaceholder = kGroqKey.isEmpty || 
                          kGroqKey.toLowerCase().contains('your_') || 
                          kGroqKey.toLowerCase().contains('api_key');
                          
    if (isPlaceholder) {
      debugPrint('DISPATCH: Groq key missing or placeholder, skipping AI phase.');
    } else {
      try {
        interpreted = await AiService.interpretVoiceAssistant(
          transcript: spokenText,
          customCommands: commandsProvider.enabledCommands,
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
        langProvider: langProvider,
      );
      if (handled) {
        debugPrint('DISPATCH: Handled by AI Intent');
        return true;
      }
    }

    final language = langProvider.selectedLanguage;
    final locale = langProvider.currentLocale;

    debugPrint('DISPATCH: Falling back to local matcher');
    
    // HARDCODED FAILSAFES: If the matching engine is struggling, we force-match core navigation.
    final normalized = spokenText.toLowerCase().trim();
    if (normalized == 'menu' || normalized == 'open menu' || normalized == 'go to menu') {
      debugPrint('FAILSAFE: Force matching Menu');
      await _execute(context, const CustomCommand(id: 'fs_menu', phrase: 'menu', action: CommandActionType.navigateMenu), ttsService, locale);
      return true;
    } else if (normalized == 'home' || normalized == 'go home' || normalized == 'back home') {
      debugPrint('FAILSAFE: Force matching Home');
      await _execute(context, const CustomCommand(id: 'fs_home', phrase: 'home', action: CommandActionType.navigateHome), ttsService, locale);
      return true;
    } else if (normalized == 'dictionary' || normalized == 'open dictionary' || normalized == 'dictionary page') {
      debugPrint('FAILSAFE: Force matching Dictionary');
      await _execute(context, const CustomCommand(id: 'fs_dict', phrase: 'dictionary', action: CommandActionType.navigateDictionary), ttsService, locale);
      return true;
    } else if (normalized == 'notes' || normalized == 'open notes') {
      debugPrint('FAILSAFE: Force matching Notes');
      await _execute(context, const CustomCommand(id: 'fs_notes', phrase: 'notes', action: CommandActionType.navigateNotes), ttsService, locale);
      return true;
    }

    final matched = commandsProvider.match(spokenText);

    if (matched == null) {
      AnalyticsService.instance.recordUnmatchedCommand(spokenText);
      if (commandsProvider.voiceFeedbackEnabled) {
        ttsService.play(
          '',
          _getFeedback(language, 'noMatch'),
          locale,
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
          _execute(context, subCommand, ttsService, locale);
        } else if (commandsProvider.voiceFeedbackEnabled) {
          ttsService.play('', 'Macro step not found: $step', locale);
        }
      }
    } else {
      _execute(context, matched, ttsService, locale);
    }

    if (commandsProvider.voiceFeedbackEnabled) {
      String feedbackText = _getFeedback(language, matched.action.name);
      if (matched.parameter != null && matched.parameter!.isNotEmpty) {
        feedbackText += ': ${matched.parameter}';
      }
      ttsService.play('', feedbackText, locale);
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
        globalNavigatorKey.currentState?.pushNamed('/dictionary');
        break;
      case CommandActionType.ttsPlay:
        if (!ttsService.isPlaying && ttsService.content != null) {
          await ttsService.togglePause(locale);
        }
        break;
      case CommandActionType.ttsPause:
        if (ttsService.isPlaying) {
          await ttsService.togglePause(locale);
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
        globalNavigatorKey.currentState!.pushNamed('/saved_assessments');
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