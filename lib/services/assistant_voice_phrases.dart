import '../custom_commands_provider.dart';
import 'document_language_service.dart';

/// Built-in assistant phrases for all six app languages (navigation, search, TTS).
class AssistantVoicePhrases {
  AssistantVoicePhrases._();

  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Tries [spokenText] against detected language, then [appLanguage], then all built-in languages.
  static CustomCommand? matchSpoken(
    String spokenText, {
    String appLanguage = 'English',
  }) {
    final detected = DocumentLanguageService.detectSpokenLanguageName(
      spokenText,
      fallback: appLanguage,
    );
    final order = <String>[
      detected,
      if (appLanguage != detected) appLanguage,
      ..._languages.where((l) => l != detected && l != appLanguage),
    ];
    for (final lang in order) {
      final hit = match(spokenText, lang);
      if (hit != null) return hit;
    }
    return null;
  }

  /// Best localized match for [spokenText], or null.
  static CustomCommand? match(String spokenText, String languageName) {
    final input = normalize(spokenText);
    if (input.isEmpty) return null;

    final param = _extractParameterized(input, languageName);
    if (param != null) {
      return CustomCommand(
        id: 'i18n_${param.action.name}',
        phrase: spokenText,
        action: param.action,
        parameter: param.parameter,
      );
    }

    final phrases = _phrasesFor(languageName);
    CustomCommand? best;
    var bestLen = 0;

    for (final entry in phrases) {
      final phrase = normalize(entry.phrase);
      if (phrase.isEmpty) continue;
      final matches = input == phrase ||
          input.startsWith('$phrase ') ||
          input.endsWith(' $phrase') ||
          input.contains(' $phrase ');
      if (!matches && input != phrase) continue;
      if (phrase.length >= bestLen) {
        bestLen = phrase.length;
        best = CustomCommand(
          id: 'i18n_${entry.action.name}_${phrase.hashCode}',
          phrase: entry.phrase,
          action: entry.action,
        );
      }
    }

    return best;
  }

  /// Keyword boost for fuzzy matcher (0 = none, up to ~0.35).
  static double keywordBoost(
    CommandActionType action,
    String input,
    String languageName,
  ) {
    final keys = _keywordsFor(action, languageName);
    for (final k in keys) {
      if (input.contains(normalize(k))) return 0.35;
    }
    return 0.0;
  }

  static const _languages = [
    'English',
    'Spanish',
    'French',
    'Arabic',
    'Turkish',
    'Chinese',
  ];

  static List<_PhraseEntry> _phrasesFor(String languageName) {
    if (_languages.contains(languageName)) {
      return _phrases[languageName]!;
    }
    return _phrases['English']!;
  }

  static List<String> _keywordsFor(
    CommandActionType action,
    String languageName,
  ) {
    final lang = _languages.contains(languageName) ? languageName : 'English';
    return _keywords[lang]?[action] ?? _keywords['English']![action] ?? [];
  }

  static _ParamMatch? _extractParameterized(String input, String languageName) {
    final lang = _languages.contains(languageName) ? languageName : 'English';

    for (final p in _dictSearchPrefixes[lang]!) {
      final prefix = normalize(p);
      if (input.startsWith(prefix)) {
        final q = input.substring(prefix.length).trim();
        if (q.isNotEmpty) {
          return _ParamMatch(
            action: CommandActionType.navigateDictionary,
            parameter: q,
          );
        }
      }
    }

    for (final p in _notesSearchPrefixes[lang]!) {
      final prefix = normalize(p);
      if (input.startsWith(prefix)) {
        final q = input.substring(prefix.length).trim();
        if (q.isNotEmpty) {
          return _ParamMatch(
            action: CommandActionType.searchNotes,
            parameter: q,
          );
        }
      }
    }

    for (final p in _librarySearchPrefixes[lang]!) {
      final prefix = normalize(p);
      if (input.startsWith(prefix)) {
        final q = input.substring(prefix.length).trim();
        if (q.isNotEmpty) {
          return _ParamMatch(
            action: CommandActionType.searchLibrary,
            parameter: q,
          );
        }
      }
    }

    return null;
  }

  static const _dictSearchPrefixes = {
    'English': [
      'search dictionary for',
      'search dictionary',
      'dictionary search',
      'find meaning of',
      'meaning of',
      'define',
    ],
    'Spanish': [
      'buscar en el diccionario',
      'buscar diccionario',
      'significado de',
      'definir',
    ],
    'French': [
      'chercher dans le dictionnaire',
      'rechercher dictionnaire',
      'signification de',
      'définir',
    ],
    'Arabic': [
      'ابحث في القاموس عن',
      'ابحث في القاموس',
      'معنى كلمة',
      'معنى',
      'عرّف',
      'عرف',
    ],
    'Turkish': [
      'sozlukte ara',
      'sözlükte ara',
      'sozlukte',
      'anlami',
      'anlamı',
      'tanimla',
      'tanımla',
    ],
    'Chinese': [
      '在词典中搜索',
      '搜索词典',
      '词典搜索',
      '意思是',
      '定义',
    ],
  };

  static const _notesSearchPrefixes = {
    'English': ['search notes for', 'search notes', 'find note'],
    'Spanish': ['buscar notas', 'buscar en notas'],
    'French': ['chercher notes', 'rechercher notes'],
    'Arabic': ['ابحث في الملاحظات عن', 'ابحث في الملاحظات'],
    'Turkish': ['notlarda ara', 'not ara'],
    'Chinese': ['搜索笔记', '查找笔记'],
  };

  static const _librarySearchPrefixes = {
    'English': ['search library for', 'search library', 'find file'],
    'Spanish': ['buscar en biblioteca', 'buscar biblioteca'],
    'French': ['chercher bibliothèque', 'rechercher bibliothèque'],
    'Arabic': ['ابحث في المكتبة عن', 'ابحث في المكتبة'],
    'Turkish': ['kutuphanede ara', 'kütüphanede ara'],
    'Chinese': ['搜索图书馆', '搜索文件'],
  };

  static const _keywords = {
    'English': {
      CommandActionType.navigateMenu: ['menu', 'option'],
      CommandActionType.navigateDictionary: ['dictionary', 'meaning', 'word', 'define'],
      CommandActionType.navigateNotes: ['notes', 'write'],
      CommandActionType.navigateHome: ['home', 'back'],
      CommandActionType.navigateHistory: ['history'],
      CommandActionType.ttsStop: ['stop', 'quit'],
      CommandActionType.ttsPause: ['pause'],
      CommandActionType.ttsPlay: ['play', 'resume', 'continue'],
    },
    'Spanish': {
      CommandActionType.navigateMenu: ['menú', 'menu', 'opciones'],
      CommandActionType.navigateDictionary: ['diccionario', 'significado', 'palabra'],
      CommandActionType.navigateNotes: ['notas', 'escribir'],
      CommandActionType.navigateHome: ['inicio', 'casa'],
      CommandActionType.navigateHistory: ['historial'],
      CommandActionType.ttsStop: ['detener', 'parar', 'fin'],
      CommandActionType.ttsPause: ['pausa'],
      CommandActionType.ttsPlay: ['reproducir', 'continuar', 'seguir'],
    },
    'French': {
      CommandActionType.navigateMenu: ['menu', 'options'],
      CommandActionType.navigateDictionary: ['dictionnaire', 'signification', 'mot'],
      CommandActionType.navigateNotes: ['notes', 'écrire'],
      CommandActionType.navigateHome: ['accueil', 'maison'],
      CommandActionType.navigateHistory: ['historique'],
      CommandActionType.ttsStop: ['arrêter', 'arreter', 'stop'],
      CommandActionType.ttsPause: ['pause'],
      CommandActionType.ttsPlay: ['lecture', 'continuer', 'reprendre'],
    },
    'Arabic': {
      CommandActionType.navigateMenu: ['قائمة', 'القائمة'],
      CommandActionType.navigateDictionary: ['قاموس', 'القاموس', 'معنى', 'كلمة'],
      CommandActionType.navigateNotes: ['ملاحظات', 'الملاحظات'],
      CommandActionType.navigateHome: ['رئيسية', 'الرئيسية', 'المنزل'],
      CommandActionType.navigateHistory: ['سجل', 'التاريخ'],
      CommandActionType.ttsStop: ['ايقاف', 'إيقاف', 'توقف', 'قف'],
      CommandActionType.ttsPause: ['وقف', 'انتظر'],
      CommandActionType.ttsPlay: ['استمر', 'تابع', 'شغل', 'تشغيل'],
    },
    'Turkish': {
      CommandActionType.navigateMenu: ['menü', 'menu', 'seçenek'],
      CommandActionType.navigateDictionary: ['sözlük', 'sozluk', 'anlam', 'kelime'],
      CommandActionType.navigateNotes: ['notlar', 'not'],
      CommandActionType.navigateHome: ['ana sayfa', 'ev'],
      CommandActionType.navigateHistory: ['geçmiş', 'gecmis', 'tarih'],
      CommandActionType.ttsStop: ['durdur', 'bitir', 'kapat'],
      CommandActionType.ttsPause: ['duraklat', 'dur'],
      CommandActionType.ttsPlay: ['oynat', 'devam', 'sürdür'],
    },
    'Chinese': {
      CommandActionType.navigateMenu: ['菜单', '选单'],
      CommandActionType.navigateDictionary: ['词典', '字典', '意思'],
      CommandActionType.navigateNotes: ['笔记'],
      CommandActionType.navigateHome: ['主页', '首页'],
      CommandActionType.navigateHistory: ['历史', '记录'],
      CommandActionType.ttsStop: ['停止', '停'],
      CommandActionType.ttsPause: ['暂停'],
      CommandActionType.ttsPlay: ['播放', '继续'],
    },
  };

  static const _phrases = {
    'English': [
      _PhraseEntry('menu', CommandActionType.navigateMenu),
      _PhraseEntry('open menu', CommandActionType.navigateMenu),
      _PhraseEntry('go to menu', CommandActionType.navigateMenu),
      _PhraseEntry('home', CommandActionType.navigateHome),
      _PhraseEntry('go home', CommandActionType.navigateHome),
      _PhraseEntry('back home', CommandActionType.navigateHome),
      _PhraseEntry('dictionary', CommandActionType.navigateDictionary),
      _PhraseEntry('open dictionary', CommandActionType.navigateDictionary),
      _PhraseEntry('dictionary page', CommandActionType.navigateDictionary),
      _PhraseEntry('notes', CommandActionType.navigateNotes),
      _PhraseEntry('open notes', CommandActionType.navigateNotes),
      _PhraseEntry('go to notes', CommandActionType.navigateNotes),
      _PhraseEntry('history', CommandActionType.navigateHistory),
      _PhraseEntry('open history', CommandActionType.navigateHistory),
      _PhraseEntry('profile', CommandActionType.navigateProfile),
      _PhraseEntry('statistics', CommandActionType.navigateStatistics),
      _PhraseEntry('about us', CommandActionType.navigateAbout),
      _PhraseEntry('contact us', CommandActionType.navigateContact),
      _PhraseEntry('faqs', CommandActionType.navigateFaqs),
      _PhraseEntry('recommendations', CommandActionType.navigateRecommendations),
      _PhraseEntry('recycle bin', CommandActionType.navigateRecycleBin),
      _PhraseEntry('languages', CommandActionType.openLanguagePicker),
      _PhraseEntry('assessments', CommandActionType.openAssessments),
      _PhraseEntry('saved docs', CommandActionType.openAssessments),
      _PhraseEntry('stop', CommandActionType.ttsStop),
      _PhraseEntry('stop reading', CommandActionType.ttsStop),
      _PhraseEntry('stop playback', CommandActionType.ttsStop),
      _PhraseEntry('pause', CommandActionType.ttsPause),
      _PhraseEntry('pause reading', CommandActionType.ttsPause),
      _PhraseEntry('play', CommandActionType.ttsPlay),
      _PhraseEntry('resume', CommandActionType.ttsPlay),
      _PhraseEntry('continue', CommandActionType.ttsPlay),
      _PhraseEntry('continue reading', CommandActionType.ttsPlay),
      _PhraseEntry('speed up', CommandActionType.ttsSpeedUp),
      _PhraseEntry('slow down', CommandActionType.ttsSlowDown),
    ],
    'Spanish': [
      _PhraseEntry('menú', CommandActionType.navigateMenu),
      _PhraseEntry('abrir menú', CommandActionType.navigateMenu),
      _PhraseEntry('ir al menú', CommandActionType.navigateMenu),
      _PhraseEntry('inicio', CommandActionType.navigateHome),
      _PhraseEntry('ir a inicio', CommandActionType.navigateHome),
      _PhraseEntry('ir a casa', CommandActionType.navigateHome),
      _PhraseEntry('diccionario', CommandActionType.navigateDictionary),
      _PhraseEntry('abrir diccionario', CommandActionType.navigateDictionary),
      _PhraseEntry('abre el diccionario', CommandActionType.navigateDictionary),
      _PhraseEntry('notas', CommandActionType.navigateNotes),
      _PhraseEntry('abrir notas', CommandActionType.navigateNotes),
      _PhraseEntry('historial', CommandActionType.navigateHistory),
      _PhraseEntry('perfil', CommandActionType.navigateProfile),
      _PhraseEntry('estadísticas', CommandActionType.navigateStatistics),
      _PhraseEntry('sobre nosotros', CommandActionType.navigateAbout),
      _PhraseEntry('contáctanos', CommandActionType.navigateContact),
      _PhraseEntry('preguntas frecuentes', CommandActionType.navigateFaqs),
      _PhraseEntry('recomendaciones', CommandActionType.navigateRecommendations),
      _PhraseEntry('papelera', CommandActionType.navigateRecycleBin),
      _PhraseEntry('idiomas', CommandActionType.openLanguagePicker),
      _PhraseEntry('evaluaciones', CommandActionType.openAssessments),
      _PhraseEntry('detener', CommandActionType.ttsStop),
      _PhraseEntry('parar', CommandActionType.ttsStop),
      _PhraseEntry('detener lectura', CommandActionType.ttsStop),
      _PhraseEntry('pausa', CommandActionType.ttsPause),
      _PhraseEntry('pausar', CommandActionType.ttsPause),
      _PhraseEntry('reproducir', CommandActionType.ttsPlay),
      _PhraseEntry('continuar', CommandActionType.ttsPlay),
      _PhraseEntry('seguir', CommandActionType.ttsPlay),
      _PhraseEntry('más rápido', CommandActionType.ttsSpeedUp),
      _PhraseEntry('más lento', CommandActionType.ttsSlowDown),
    ],
    'French': [
      _PhraseEntry('menu', CommandActionType.navigateMenu),
      _PhraseEntry('ouvrir le menu', CommandActionType.navigateMenu),
      _PhraseEntry('accueil', CommandActionType.navigateHome),
      _PhraseEntry('aller à l\'accueil', CommandActionType.navigateHome),
      _PhraseEntry('dictionnaire', CommandActionType.navigateDictionary),
      _PhraseEntry('ouvrir le dictionnaire', CommandActionType.navigateDictionary),
      _PhraseEntry('notes', CommandActionType.navigateNotes),
      _PhraseEntry('ouvrir les notes', CommandActionType.navigateNotes),
      _PhraseEntry('historique', CommandActionType.navigateHistory),
      _PhraseEntry('profil', CommandActionType.navigateProfile),
      _PhraseEntry('statistiques', CommandActionType.navigateStatistics),
      _PhraseEntry('à propos', CommandActionType.navigateAbout),
      _PhraseEntry('nous contacter', CommandActionType.navigateContact),
      _PhraseEntry('faq', CommandActionType.navigateFaqs),
      _PhraseEntry('recommandations', CommandActionType.navigateRecommendations),
      _PhraseEntry('corbeille', CommandActionType.navigateRecycleBin),
      _PhraseEntry('langues', CommandActionType.openLanguagePicker),
      _PhraseEntry('arrêter', CommandActionType.ttsStop),
      _PhraseEntry('stop', CommandActionType.ttsStop),
      _PhraseEntry('pause', CommandActionType.ttsPause),
      _PhraseEntry('lecture', CommandActionType.ttsPlay),
      _PhraseEntry('continuer', CommandActionType.ttsPlay),
      _PhraseEntry('reprendre', CommandActionType.ttsPlay),
      _PhraseEntry('plus vite', CommandActionType.ttsSpeedUp),
      _PhraseEntry('plus lentement', CommandActionType.ttsSlowDown),
    ],
    'Arabic': [
      _PhraseEntry('القائمة', CommandActionType.navigateMenu),
      _PhraseEntry('افتح القائمة', CommandActionType.navigateMenu),
      _PhraseEntry('القائمة الرئيسية', CommandActionType.navigateMenu),
      _PhraseEntry('الرئيسية', CommandActionType.navigateHome),
      _PhraseEntry('الصفحة الرئيسية', CommandActionType.navigateHome),
      _PhraseEntry('اذهب للرئيسية', CommandActionType.navigateHome),
      _PhraseEntry('القاموس', CommandActionType.navigateDictionary),
      _PhraseEntry('افتح القاموس', CommandActionType.navigateDictionary),
      _PhraseEntry('فتح القاموس', CommandActionType.navigateDictionary),
      _PhraseEntry('الملاحظات', CommandActionType.navigateNotes),
      _PhraseEntry('افتح الملاحظات', CommandActionType.navigateNotes),
      _PhraseEntry('فتح الملاحظات', CommandActionType.navigateNotes),
      _PhraseEntry('السجل', CommandActionType.navigateHistory),
      _PhraseEntry('التاريخ', CommandActionType.navigateHistory),
      _PhraseEntry('افتح السجل', CommandActionType.navigateHistory),
      _PhraseEntry('الملف الشخصي', CommandActionType.navigateProfile),
      _PhraseEntry('الإحصائيات', CommandActionType.navigateStatistics),
      _PhraseEntry('من نحن', CommandActionType.navigateAbout),
      _PhraseEntry('اتصل بنا', CommandActionType.navigateContact),
      _PhraseEntry('الأسئلة الشائعة', CommandActionType.navigateFaqs),
      _PhraseEntry('التوصيات', CommandActionType.navigateRecommendations),
      _PhraseEntry('سلة المحذوفات', CommandActionType.navigateRecycleBin),
      _PhraseEntry('اللغات', CommandActionType.openLanguagePicker),
      _PhraseEntry('التقييمات', CommandActionType.openAssessments),
      _PhraseEntry('ايقاف', CommandActionType.ttsStop),
      _PhraseEntry('إيقاف', CommandActionType.ttsStop),
      _PhraseEntry('توقف', CommandActionType.ttsStop),
      _PhraseEntry('وقف القراءة', CommandActionType.ttsStop),
      _PhraseEntry('إيقاف القراءة', CommandActionType.ttsStop),
      _PhraseEntry('توقف مؤقت', CommandActionType.ttsPause),
      _PhraseEntry('انتظر', CommandActionType.ttsPause),
      _PhraseEntry('استمر', CommandActionType.ttsPlay),
      _PhraseEntry('تابع', CommandActionType.ttsPlay),
      _PhraseEntry('شغل', CommandActionType.ttsPlay),
      _PhraseEntry('تشغيل', CommandActionType.ttsPlay),
      _PhraseEntry('أسرع', CommandActionType.ttsSpeedUp),
      _PhraseEntry('أبطأ', CommandActionType.ttsSlowDown),
    ],
    'Turkish': [
      _PhraseEntry('menü', CommandActionType.navigateMenu),
      _PhraseEntry('menüyü aç', CommandActionType.navigateMenu),
      _PhraseEntry('ana sayfa', CommandActionType.navigateHome),
      _PhraseEntry('eve git', CommandActionType.navigateHome),
      _PhraseEntry('sözlük', CommandActionType.navigateDictionary),
      _PhraseEntry('sozluk', CommandActionType.navigateDictionary),
      _PhraseEntry('sözlüğü aç', CommandActionType.navigateDictionary),
      _PhraseEntry('sozlugu ac', CommandActionType.navigateDictionary),
      _PhraseEntry('notlar', CommandActionType.navigateNotes),
      _PhraseEntry('notları aç', CommandActionType.navigateNotes),
      _PhraseEntry('geçmiş', CommandActionType.navigateHistory),
      _PhraseEntry('gecmis', CommandActionType.navigateHistory),
      _PhraseEntry('profil', CommandActionType.navigateProfile),
      _PhraseEntry('istatistikler', CommandActionType.navigateStatistics),
      _PhraseEntry('hakkımızda', CommandActionType.navigateAbout),
      _PhraseEntry('bize ulaşın', CommandActionType.navigateContact),
      _PhraseEntry('sss', CommandActionType.navigateFaqs),
      _PhraseEntry('öneriler', CommandActionType.navigateRecommendations),
      _PhraseEntry('geri dönüşüm', CommandActionType.navigateRecycleBin),
      _PhraseEntry('diller', CommandActionType.openLanguagePicker),
      _PhraseEntry('durdur', CommandActionType.ttsStop),
      _PhraseEntry('okumayı durdur', CommandActionType.ttsStop),
      _PhraseEntry('duraklat', CommandActionType.ttsPause),
      _PhraseEntry('oynat', CommandActionType.ttsPlay),
      _PhraseEntry('devam et', CommandActionType.ttsPlay),
      _PhraseEntry('daha hızlı', CommandActionType.ttsSpeedUp),
      _PhraseEntry('daha yavaş', CommandActionType.ttsSlowDown),
    ],
    'Chinese': [
      _PhraseEntry('菜单', CommandActionType.navigateMenu),
      _PhraseEntry('打开菜单', CommandActionType.navigateMenu),
      _PhraseEntry('主页', CommandActionType.navigateHome),
      _PhraseEntry('首页', CommandActionType.navigateHome),
      _PhraseEntry('回到主页', CommandActionType.navigateHome),
      _PhraseEntry('词典', CommandActionType.navigateDictionary),
      _PhraseEntry('字典', CommandActionType.navigateDictionary),
      _PhraseEntry('打开词典', CommandActionType.navigateDictionary),
      _PhraseEntry('笔记', CommandActionType.navigateNotes),
      _PhraseEntry('打开笔记', CommandActionType.navigateNotes),
      _PhraseEntry('历史', CommandActionType.navigateHistory),
      _PhraseEntry('打开历史', CommandActionType.navigateHistory),
      _PhraseEntry('个人资料', CommandActionType.navigateProfile),
      _PhraseEntry('统计', CommandActionType.navigateStatistics),
      _PhraseEntry('关于我们', CommandActionType.navigateAbout),
      _PhraseEntry('联系我们', CommandActionType.navigateContact),
      _PhraseEntry('常见问题', CommandActionType.navigateFaqs),
      _PhraseEntry('推荐', CommandActionType.navigateRecommendations),
      _PhraseEntry('回收站', CommandActionType.navigateRecycleBin),
      _PhraseEntry('语言', CommandActionType.openLanguagePicker),
      _PhraseEntry('停止', CommandActionType.ttsStop),
      _PhraseEntry('停止阅读', CommandActionType.ttsStop),
      _PhraseEntry('暂停', CommandActionType.ttsPause),
      _PhraseEntry('播放', CommandActionType.ttsPlay),
      _PhraseEntry('继续', CommandActionType.ttsPlay),
      _PhraseEntry('继续阅读', CommandActionType.ttsPlay),
      _PhraseEntry('快一点', CommandActionType.ttsSpeedUp),
      _PhraseEntry('慢一点', CommandActionType.ttsSlowDown),
    ],
  };

  static const _listeningAck = {
    'English': 'Hey! I am listening.',
    'Spanish': '¡Hola! Te escucho.',
    'French': 'Salut ! Je vous écoute.',
    'Arabic': 'مرحباً! أنا أستمع.',
    'Turkish': 'Merhaba! Dinliyorum.',
    'Chinese': '你好！我在听。',
  };

  static String listeningAck(String languageName) =>
      _listeningAck[languageName] ?? _listeningAck['English']!;
}

class _PhraseEntry {
  final String phrase;
  final CommandActionType action;
  const _PhraseEntry(this.phrase, this.action);
}

class _ParamMatch {
  final CommandActionType action;
  final String parameter;
  const _ParamMatch({required this.action, required this.parameter});
}
