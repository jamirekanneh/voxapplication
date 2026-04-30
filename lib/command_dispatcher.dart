import 'package:flutter/material.dart';
import 'custom_commands_provider.dart';
import 'tts_service.dart';
import 'language_provider.dart';
import 'analytics_service.dart';

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
  static Future<bool> dispatch({
    required BuildContext context,
    required String spokenText,
    required CustomCommandsProvider commandsProvider,
    required TtsService ttsService,
    required LanguageProvider langProvider,
  }) async {
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