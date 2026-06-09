import 'reading_voice_keyword.dart';

/// Multilingual read-aloud voice triggers for all six app languages.
class ReadingVoiceKeywordsI18n {
  ReadingVoiceKeywordsI18n._();

  static String codeForLanguage(String languageName) {
    switch (languageName) {
      case 'Spanish':
        return 'es';
      case 'French':
        return 'fr';
      case 'Arabic':
        return 'ar';
      case 'Turkish':
        return 'tr';
      case 'Chinese':
        return 'zh';
      default:
        return 'en';
    }
  }

  static Set<String> _words(String lang, ReadingVoiceKeyword keyword) {
    return _table[lang]?[keyword] ?? _table['en']![keyword]!;
  }

  static Set<String> pauseWords(String languageName) =>
      _words(codeForLanguage(languageName), ReadingVoiceKeyword.pause);

  static Set<String> stopWords(String languageName) =>
      _words(codeForLanguage(languageName), ReadingVoiceKeyword.stop);

  static Set<String> playWords(String languageName) =>
      _words(codeForLanguage(languageName), ReadingVoiceKeyword.play);

  static Set<String> forwardWords(String languageName) =>
      _words(codeForLanguage(languageName), ReadingVoiceKeyword.forward);

  static Set<String> backwardWords(String languageName) =>
      _words(codeForLanguage(languageName), ReadingVoiceKeyword.backward);

  static Set<String> highlightWords(String languageName) =>
      _words(codeForLanguage(languageName), ReadingVoiceKeyword.highlight);

  static List<String> pausePhrases(String languageName) =>
      _phrases[codeForLanguage(languageName)]?['pause'] ??
      _phrases['en']!['pause']!;

  static List<String> stopPhrases(String languageName) =>
      _phrases[codeForLanguage(languageName)]?['stop'] ??
      _phrases['en']!['stop']!;

  static List<String> playPhrases(String languageName) =>
      _phrases[codeForLanguage(languageName)]?['play'] ??
      _phrases['en']!['play']!;

  static List<String> forwardPhrases(String languageName) =>
      _phrases[codeForLanguage(languageName)]?['forward'] ??
      _phrases['en']!['forward']!;

  static List<String> backwardPhrases(String languageName) =>
      _phrases[codeForLanguage(languageName)]?['backward'] ??
      _phrases['en']!['backward']!;

  static List<String> highlightPhrases(String languageName) =>
      _phrases[codeForLanguage(languageName)]?['highlight'] ??
      _phrases['en']!['highlight']!;

  static String feedback(ReadingVoiceKeyword keyword, String languageName) {
    final code = codeForLanguage(languageName);
    return _feedback[code]?[keyword] ?? _feedback['en']![keyword]!;
  }

  static const _feedback = <String, Map<ReadingVoiceKeyword, String>>{
    'en': {
      ReadingVoiceKeyword.pause: '⏸ Paused',
      ReadingVoiceKeyword.stop: '🛑 Stopped',
      ReadingVoiceKeyword.play: '▶ Playing',
      ReadingVoiceKeyword.forward: '⏭ Forward',
      ReadingVoiceKeyword.backward: '⏮ Back',
      ReadingVoiceKeyword.highlight: '🖍️ Highlighted',
    },
    'es': {
      ReadingVoiceKeyword.pause: '⏸ En pausa',
      ReadingVoiceKeyword.stop: '🛑 Detenido',
      ReadingVoiceKeyword.play: '▶ Reproduciendo',
      ReadingVoiceKeyword.forward: '⏭ Adelante',
      ReadingVoiceKeyword.backward: '⏮ Atrás',
      ReadingVoiceKeyword.highlight: '🖍️ Resaltado',
    },
    'fr': {
      ReadingVoiceKeyword.pause: '⏸ En pause',
      ReadingVoiceKeyword.stop: '🛑 Arrêté',
      ReadingVoiceKeyword.play: '▶ Lecture',
      ReadingVoiceKeyword.forward: '⏭ Avancer',
      ReadingVoiceKeyword.backward: '⏮ Reculer',
      ReadingVoiceKeyword.highlight: '🖍️ Surligné',
    },
    'ar': {
      ReadingVoiceKeyword.pause: '⏸ متوقف مؤقتاً',
      ReadingVoiceKeyword.stop: '🛑 توقف',
      ReadingVoiceKeyword.play: '▶ يعمل',
      ReadingVoiceKeyword.forward: '⏭ للأمام',
      ReadingVoiceKeyword.backward: '⏮ للخلف',
      ReadingVoiceKeyword.highlight: '🖍️ مُميَّز',
    },
    'tr': {
      ReadingVoiceKeyword.pause: '⏸ Duraklatıldı',
      ReadingVoiceKeyword.stop: '🛑 Durduruldu',
      ReadingVoiceKeyword.play: '▶ Oynatılıyor',
      ReadingVoiceKeyword.forward: '⏭ İleri',
      ReadingVoiceKeyword.backward: '⏮ Geri',
      ReadingVoiceKeyword.highlight: '🖍️ Vurgulandı',
    },
    'zh': {
      ReadingVoiceKeyword.pause: '⏸ 已暂停',
      ReadingVoiceKeyword.stop: '🛑 已停止',
      ReadingVoiceKeyword.play: '▶ 播放中',
      ReadingVoiceKeyword.forward: '⏭ 前进',
      ReadingVoiceKeyword.backward: '⏮ 后退',
      ReadingVoiceKeyword.highlight: '🖍️ 已高亮',
    },
  };

  static const _table = <String, Map<ReadingVoiceKeyword, Set<String>>>{
    'en': {
      ReadingVoiceKeyword.pause: {'pause', 'paws', 'halt', 'wait', 'hold'},
      ReadingVoiceKeyword.stop: {'stop', 'end', 'quit'},
      ReadingVoiceKeyword.play: {
        'play',
        'resume',
        'continue',
        'unpause',
        'start',
        'read',
      },
      ReadingVoiceKeyword.forward: {'forward', 'skip', 'next'},
      ReadingVoiceKeyword.backward: {'back', 'backward', 'rewind', 'previous'},
      ReadingVoiceKeyword.highlight: {'highlight', 'mark'},
    },
    'es': {
      ReadingVoiceKeyword.pause: {'pausa', 'detener', 'espera', 'alto'},
      ReadingVoiceKeyword.stop: {'parar', 'detener', 'fin', 'terminar'},
      ReadingVoiceKeyword.play: {
        'reproducir',
        'continuar',
        'seguir',
        'leer',
        'iniciar',
        'play',
      },
      ReadingVoiceKeyword.forward: {'adelante', 'avanzar', 'siguiente', 'saltar'},
      ReadingVoiceKeyword.backward: {'atras', 'atrás', 'retroceder', 'anterior'},
      ReadingVoiceKeyword.highlight: {'resaltar', 'marcar', 'subrayar'},
    },
    'fr': {
      ReadingVoiceKeyword.pause: {'pause', 'arrete', 'arrête', 'attends', 'stop'},
      ReadingVoiceKeyword.stop: {'stop', 'arreter', 'arrêter', 'fin', 'quitter'},
      ReadingVoiceKeyword.play: {
        'lecture',
        'jouer',
        'continuer',
        'reprendre',
        'lire',
        'play',
      },
      ReadingVoiceKeyword.forward: {'avancer', 'suivant', 'avant'},
      ReadingVoiceKeyword.backward: {'reculer', 'retour', 'precedent', 'précédent'},
      ReadingVoiceKeyword.highlight: {'surligner', 'marquer', 'surligne'},
    },
    'ar': {
      ReadingVoiceKeyword.pause: {'توقف', 'وقف', 'انتظر', 'اصبر'},
      ReadingVoiceKeyword.stop: {'ايقاف', 'إيقاف', 'انهاء', 'إنهاء', 'قف'},
      ReadingVoiceKeyword.play: {'استمر', 'تابع', 'اكمل', 'أكمل', 'شغل', 'تشغيل'},
      ReadingVoiceKeyword.forward: {'امام', 'أمام', 'التالي', 'تقدم'},
      ReadingVoiceKeyword.backward: {'خلف', 'السابق', 'تراجع'},
      ReadingVoiceKeyword.highlight: {'تمييز', 'علم', 'حدد'},
    },
    'tr': {
      ReadingVoiceKeyword.pause: {'duraklat', 'dur', 'bekle', 'bekleme'},
      ReadingVoiceKeyword.stop: {'durdur', 'bitir', 'kapat', 'son'},
      ReadingVoiceKeyword.play: {
        'oynat',
        'devam',
        'baslat',
        'başlat',
        'oku',
        'sürdür',
      },
      ReadingVoiceKeyword.forward: {'ileri', 'sonraki', 'atla'},
      ReadingVoiceKeyword.backward: {'geri', 'onceki', 'önceki'},
      ReadingVoiceKeyword.highlight: {'vurgula', 'isaretle', 'işaretle'},
    },
    'zh': {
      ReadingVoiceKeyword.pause: {'暂停', '停', '等一下'},
      ReadingVoiceKeyword.stop: {'停止', '结束', '停'},
      ReadingVoiceKeyword.play: {'播放', '继续', '开始', '读'},
      ReadingVoiceKeyword.forward: {'前进', '下一个', '往前'},
      ReadingVoiceKeyword.backward: {'后退', '上一个', '往后'},
      ReadingVoiceKeyword.highlight: {'高亮', '标记', '标注'},
    },
  };

  static const _phrases = <String, Map<String, List<String>>>{
    'en': {
      'pause': ['pause reading', 'hold on', 'hold up'],
      'stop': ['stop reading', 'stop playback', 'end reading'],
      'play': ['continue reading', 'keep reading', 'start reading'],
      'forward': ['go forward', 'skip ahead'],
      'backward': ['go back'],
      'highlight': [
        'highlight that',
        'mark text',
        'mark this',
        'highlight text',
      ],
    },
    'es': {
      'pause': ['pausa lectura', 'detener lectura'],
      'stop': ['parar lectura', 'detener reproduccion'],
      'play': ['continuar lectura', 'seguir leyendo'],
      'forward': ['ir adelante', 'saltar adelante'],
      'backward': ['ir atras', 'ir atrás'],
      'highlight': ['resaltar texto', 'marcar texto'],
    },
    'fr': {
      'pause': ['pause lecture', 'arreter lecture'],
      'stop': ['stop lecture', 'fin lecture'],
      'play': ['continuer lecture', 'reprendre lecture'],
      'forward': ['aller avant', 'avancer'],
      'backward': ['aller arriere', 'reculer'],
      'highlight': ['surligner texte', 'marquer texte'],
    },
    'ar': {
      'pause': ['وقف القراءة', 'توقف عن القراءة'],
      'stop': ['ايقاف القراءة', 'إيقاف القراءة'],
      'play': ['استمر بالقراءة', 'تابع القراءة'],
      'forward': ['الى الامام', 'إلى الأمام'],
      'backward': ['الى الخلف', 'إلى الخلف'],
      'highlight': ['ميز الجملة', 'علم النص'],
    },
    'tr': {
      'pause': ['okumayi duraklat', 'okumayı duraklat'],
      'stop': ['okumayi durdur', 'okumayı durdur'],
      'play': ['okumaya devam', 'devam et'],
      'forward': ['ileri git'],
      'backward': ['geri git'],
      'highlight': ['cumleyi vurgula', 'cümleyi vurgula'],
    },
    'zh': {
      'pause': ['暂停阅读', '暂停朗读'],
      'stop': ['停止阅读', '停止朗读'],
      'play': ['继续阅读', '继续朗读'],
      'forward': ['向前', '前进十秒'],
      'backward': ['向后', '后退十秒'],
      'highlight': ['高亮句子', '标记文本'],
    },
  };
}
