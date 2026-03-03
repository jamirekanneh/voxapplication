import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_strings.dart';

class LanguageProvider extends ChangeNotifier {
  static const _prefKey = 'selected_language';

  String _selectedLanguage = 'English';

  final List<String> languages = [
    'English',
    'Spanish',
    'French',
    'Arabic',
    'Turkish',
    'Chinese',
  ];

  // TTS locale map
  static const Map<String, String> _ttsLocales = {
    'English':  'en-US',
    'Spanish':  'es-ES',
    'French':   'fr-FR',
    'Arabic':   'ar-SA',
    'Turkish':  'tr-TR',
    'Chinese':  'zh-CN',
  };

  // STT locale map
  static const Map<String, String> _sttLocales = {
    'English':  'en_US',
    'Spanish':  'es_ES',
    'French':   'fr_FR',
    'Arabic':   'ar_SA',
    'Turkish':  'tr_TR',
    'Chinese':  'zh_CN',
  };

  String get selectedLanguage => _selectedLanguage;
  String get ttsLocale => _ttsLocales[_selectedLanguage] ?? 'en-US';
  String get sttLocale => _sttLocales[_selectedLanguage] ?? 'en_US';

  // Translate shortcut
  String t(String key) => AppStrings.of(_selectedLanguage)[key] ?? key;

  LanguageProvider() {
    _loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null && languages.contains(saved)) {
      _selectedLanguage = saved;
      notifyListeners();
    }
  }

  Future<void> setLanguage(String language) async {
    if (_selectedLanguage == language) return;
    _selectedLanguage = language;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, language);
  }
}