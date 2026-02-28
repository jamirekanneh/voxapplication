import 'package:flutter/material.dart';

class LanguageProvider extends ChangeNotifier {
  // Map: display name → TTS locale code
  static const Map<String, String> languageLocales = {
    "English": "en-US",
    "Spanish": "es-ES",
    "Chinese": "zh-CN",
    "Turkish": "tr-TR",
    "Arabic": "ar-SA",
    "French": "fr-FR",
  };

  // Map: display name → STT locale code
  static const Map<String, String> sttLocales = {
    "English": "en_US",
    "Spanish": "es_ES",
    "Chinese": "zh_CN",
    "Turkish": "tr_TR",
    "Arabic": "ar_SA",
    "French": "fr_FR",
  };

  String _selectedLanguage = "English";

  String get selectedLanguage => _selectedLanguage;

  String get ttsLocale => languageLocales[_selectedLanguage] ?? "en-US";

  String get sttLocale => sttLocales[_selectedLanguage] ?? "en_US";

  void setLanguage(String language) {
    if (languageLocales.containsKey(language)) {
      _selectedLanguage = language;
      notifyListeners();
    }
  }

  List<String> get languages => languageLocales.keys.toList();
}
