import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Detects document language and maps to TTS / OCR settings for all six app languages.
class DocumentLanguageService {
  DocumentLanguageService._();

  static const languageNames = [
    'English',
    'Spanish',
    'French',
    'Arabic',
    'Turkish',
    'Chinese',
  ];

  static const Map<String, String> ttsLocales = {
    'English': 'en-US',
    'Spanish': 'es-ES',
    'French': 'fr-FR',
    'Arabic': 'ar-SA',
    'Turkish': 'tr-TR',
    'Chinese': 'zh-CN',
  };

  static String ttsLocaleForLanguage(String languageName) =>
      ttsLocales[languageName] ?? 'en-US';

  static String languageNameFromTtsLocale(String locale) {
    final prefix = locale.split('-').first.split('_').first.toLowerCase();
    for (final entry in ttsLocales.entries) {
      if (entry.value.split('-').first.toLowerCase() == prefix) {
        return entry.key;
      }
    }
    return 'English';
  }

  /// Picks the best TTS locale for [text], using [fallbackLanguage] when ambiguous.
  static String detectTtsLocale(
    String text, {
    String fallbackLanguage = 'English',
  }) {
    return ttsLocaleForLanguage(
      detectLanguageName(text, fallback: fallbackLanguage),
    );
  }

  static String detectLanguageName(
    String text, {
    String fallback = 'English',
  }) {
    final sample = text.length > 5000 ? text.substring(0, 5000) : text;
    if (sample.trim().isEmpty) return fallback;

    var arabic = 0;
    var cjk = 0;
    var turkish = 0;
    var french = 0;
    var spanish = 0;
    var latin = 0;

    for (final rune in sample.runes) {
      if (_isArabic(rune)) {
        arabic++;
      } else if (_isCjk(rune)) {
        cjk++;
      } else if (_isLatinLetter(rune)) {
        latin++;
        if (_turkishChars.contains(rune)) turkish++;
        if (_frenchChars.contains(rune)) french++;
        if (_spanishChars.contains(rune)) spanish++;
      }
    }

    final total = arabic + cjk + latin;
    if (total < 12) return fallback;

    if (arabic > total * 0.12) return 'Arabic';
    if (cjk > total * 0.12) return 'Chinese';

    if (turkish >= 3 && turkish >= french && turkish >= spanish) {
      return 'Turkish';
    }
    if (spanish >= 3 && spanish > french) return 'Spanish';
    if (french >= 3) return 'French';

    if (languageNames.contains(fallback)) return fallback;
    return 'English';
  }

  /// Detects language from a short voice command or chat message (lower bar than [detectLanguageName]).
  static String detectSpokenLanguageName(
    String text, {
    String fallback = 'English',
  }) {
    final sample = text.trim();
    if (sample.isEmpty) return fallback;

    var arabic = 0;
    var cjk = 0;
    var turkish = 0;
    var french = 0;
    var spanish = 0;
    var latin = 0;

    for (final rune in sample.runes) {
      if (_isArabic(rune)) {
        arabic++;
      } else if (_isCjk(rune)) {
        cjk++;
      } else if (_isLatinLetter(rune)) {
        latin++;
        if (_turkishChars.contains(rune)) turkish++;
        if (_frenchChars.contains(rune)) french++;
        if (_spanishChars.contains(rune)) spanish++;
      }
    }

    final total = arabic + cjk + latin;
    if (total < 2) return fallback;

    if (arabic > 0 && arabic >= latin && arabic >= cjk) return 'Arabic';
    if (cjk > 0 && cjk >= latin) return 'Chinese';

    if (turkish >= 2 && turkish >= french && turkish >= spanish) {
      return 'Turkish';
    }
    if (spanish >= 2 && spanish > french) return 'Spanish';
    if (french >= 2) return 'French';

    if (languageNames.contains(fallback)) return fallback;
    return 'English';
  }

  static bool isRtlLocale(String ttsLocale) {
    final prefix = ttsLocale.split('-').first.toLowerCase();
    return prefix == 'ar' || prefix == 'he' || prefix == 'fa' || prefix == 'ur';
  }

  static TextRecognitionScript ocrScriptForLanguage(String languageName) {
    switch (languageName) {
      case 'Chinese':
        return TextRecognitionScript.chinese;
      default:
        return TextRecognitionScript.latin;
    }
  }

  /// OCR scripts to try, ordered by likely match for [languageName].
  static List<TextRecognitionScript> ocrScriptsToTry(String languageName) {
    final primary = ocrScriptForLanguage(languageName);
    if (primary == TextRecognitionScript.chinese) {
      return [TextRecognitionScript.chinese, TextRecognitionScript.latin];
    }
    return [TextRecognitionScript.latin, TextRecognitionScript.chinese];
  }

  /// Camera/gallery scans — try every on-device script (typed, handwriting, screens).
  static List<TextRecognitionScript> ocrScriptsForScan(String languageName) {
    const all = [
      TextRecognitionScript.latin,
      TextRecognitionScript.chinese,
      TextRecognitionScript.devanagiri,
      TextRecognitionScript.japanese,
      TextRecognitionScript.korean,
    ];
    final primary = ocrScriptForLanguage(languageName);
    return [primary, ...all.where((s) => s != primary)];
  }

  static bool _isArabic(int rune) =>
      (rune >= 0x0600 && rune <= 0x06FF) ||
      (rune >= 0x0750 && rune <= 0x077F) ||
      (rune >= 0x08A0 && rune <= 0x08FF) ||
      (rune >= 0xFB50 && rune <= 0xFDFF) ||
      (rune >= 0xFE70 && rune <= 0xFEFF);

  static bool _isCjk(int rune) =>
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x3000 && rune <= 0x303F);

  static bool _isLatinLetter(int rune) =>
      (rune >= 0x0041 && rune <= 0x007A) ||
      (rune >= 0x00C0 && rune <= 0x024F);

  static const _turkishChars = {0x011F, 0x011E, 0x015F, 0x015E, 0x0131, 0x0130, 0x00F6, 0x00D6, 0x00FC, 0x00DC, 0x00E7, 0x00C7};
  static const _frenchChars = {0x00E9, 0x00E8, 0x00EA, 0x00EB, 0x00E0, 0x00E2, 0x00F4, 0x00EE, 0x00FB, 0x00E7, 0x0153, 0x0152};
  static const _spanishChars = {0x00F1, 0x00D1, 0x00BF, 0x00A1, 0x00E1, 0x00ED, 0x00F3, 0x00FA, 0x00FC};

  /// Normalize document text for read-aloud + highlight offsets (stable across sessions).
  static String normalizeReaderText(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? raw.trim() : cleaned;
  }
}
