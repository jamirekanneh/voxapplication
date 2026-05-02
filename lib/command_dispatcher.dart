import 'package:flutter/material.dart';
import 'ai_service.dart';
import 'analytics_service.dart';
import 'custom_commands_provider.dart';
import 'language_provider.dart';
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
      case VoiceAssistantAction.none:
      case VoiceAssistantAction.unknown:
      case VoiceAssistantAction.assistantOff:
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
            await ttsService.play('', r, locale);
          } else {
            await ttsService.play('', _getFeedback(language, 'noMatch'), locale);
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
          await ttsService.play('', feedbackText, locale);
        }

        if (!context.mounted) return true;

        await _execute(context, cmd, ttsService, locale);

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
    try {
      interpreted = await AiService.interpretVoiceAssistant(
        transcript: spokenText,
      );
    } catch (_) {
      interpreted = null;
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
      if (handled) return true;
    }

    final matched = commandsProvider.match(spokenText);
    final language = langProvider.selectedLanguage;
    final locale = langProvider.currentLocale;

    if (matched == null) {
      AnalyticsService.instance.recordUnmatchedCommand(spokenText);
      if (commandsProvider.voiceFeedbackEnabled) {
        await ttsService.play(
          '',
          _getFeedback(language, 'noMatch'),
          locale,
        );
      }
      return false;
    }

    // Track voice command usage
    AnalyticsService.instance.recordVoiceCommand(matched.action.displayName);

    if (commandsProvider.voiceFeedbackEnabled) {
      String feedbackText = _getFeedback(language, matched.action.name);
      if (matched.parameter != null && matched.parameter!.isNotEmpty) {
        feedbackText += ': ${matched.parameter}';
      }
      await ttsService.play('', feedbackText, locale);
    }

    if (!context.mounted) return true;

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
          await _execute(context, subCommand, ttsService, locale);
        } else if (commandsProvider.voiceFeedbackEnabled) {
          await ttsService.play('',
              'Macro step not found: $step', locale); // spoken fallback
        }
      }
      return true;
    }

    await _execute(context, matched, ttsService, locale);
    return true;
  }

  static Future<void> _execute(
    BuildContext context,
    CustomCommand command,
    TtsService ttsService,
    String locale,
  ) async {
    switch (command.action) {
      // FIX: pushNamed instead of pushReplacementNamed — replacement
      // destroys the GlobalSttWrapper state, breaking all future voice commands
      case CommandActionType.navigateHome:
        Navigator.pushNamed(context, '/home');
        break;
      case CommandActionType.navigateNotes:
        Navigator.pushNamed(context, '/notes');
        break;
      case CommandActionType.navigateMenu:
        Navigator.pushNamed(context, '/menu');
        break;
      case CommandActionType.navigateDictionary:
        Navigator.pushNamed(context, '/dictionary');
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
        Navigator.pushNamed(
          context,
          '/notes',
          arguments: {'searchQuery': command.parameter ?? ''},
        );
        break;
      case CommandActionType.openNote:
        Navigator.pushNamed(
          context,
          '/notes',
          arguments: {'openNote': command.parameter ?? ''},
        );
        break;
      case CommandActionType.searchLibrary:
        Navigator.pushNamed(
          context,
          '/home',
          arguments: {'searchQuery': command.parameter ?? ''},
        );
        break;
      case CommandActionType.openAssessments:
        Navigator.pushNamed(context, '/saved_assessments');
        break;
      case CommandActionType.macroSequence:
        // Macro logic is handled in dispatch; no direct action here.
        break;
    }
  }
}