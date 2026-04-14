import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translator/translator.dart';
import 'app_strings.dart';

class LanguageProvider extends ChangeNotifier {
  static const _prefKey = 'selected_language';
  static const _cacheKeyPrefix = 'translation_cache_'; // new dynamic cache

  String _selectedLanguage = 'English';
  final _translator = GoogleTranslator();

  // Dynamic cache for strings not found in app_strings.dart
  Map<String, String> _dynamicTranslations = {};
  
  // To avoid spamming the translate API with the same string
  final Set<String> _translatingSet = {};

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

  // Google Translator API lang codes
  static const Map<String, String> _translatorCodeMap = {
    'Spanish':  'es',
    'French':   'fr',
    'Arabic':   'ar',
    'Turkish':  'tr',
    'Chinese':  'zh-cn',
  };

  String get selectedLanguage => _selectedLanguage;
  String get ttsLocale => _ttsLocales[_selectedLanguage] ?? 'en-US';
  String get sttLocale => _sttLocales[_selectedLanguage] ?? 'en_US';
  String get currentLocale => ttsLocale;

  LanguageProvider() {
    _loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null && languages.contains(saved)) {
      _selectedLanguage = saved;
    }
    await _loadDynamicCache();
    notifyListeners();
  }

  Future<void> setLanguage(String language) async {
    if (_selectedLanguage == language) return;
    _selectedLanguage = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, language);
    
    // Switch dynamic cache
    await _loadDynamicCache();
    notifyListeners();
  }

  Future<void> _loadDynamicCache() async {
    if (_selectedLanguage == 'English') {
      _dynamicTranslations.clear();
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '$_cacheKeyPrefix$_selectedLanguage';
    final raw = prefs.getString(cacheKey);
    
    if (raw != null) {
      try {
        _dynamicTranslations = Map<String, String>.from(jsonDecode(raw) as Map);
      } catch (_) {
        _dynamicTranslations = {};
      }
    } else {
      _dynamicTranslations = {};
    }
  }

  Future<void> _saveDynamicCache() async {
    if (_selectedLanguage == 'English') return;
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '$_cacheKeyPrefix$_selectedLanguage';
    await prefs.setString(cacheKey, jsonEncode(_dynamicTranslations));
  }

  // ─────────────────────────────────────────────────────────────
  // TRANSLATION SHORTCUT
  // First checks standard `app_strings.dart`.
  // If missing and language is not English, instantly returns the 
  // English phrase and fires off a background request to translate it.
  // When translated, it caches and injects directly via notifyListeners().
  // ─────────────────────────────────────────────────────────────
  String t(String key) {
    // 1. Fallback base text is either English from AppStrings or the key itself
    final baseEnText = AppStrings.of('English')[key] ?? key;

    // 2. English is always instant
    if (_selectedLanguage == 'English') {
      return baseEnText;
    }

    // 3. Try to get native manual translation
    final langDict = AppStrings.of(_selectedLanguage);
    if (langDict.containsKey(key)) {
      return langDict[key]!;
    }

    // 4. Try dynamic cache
    if (_dynamicTranslations.containsKey(key)) {
      return _dynamicTranslations[key]!;
    }

    // 5. Fire auto-translation async if not already requesting it
    if (!_translatingSet.contains(key)) {
      _translateAsync(key, baseEnText);
    }

    // 6. Return English text temporarily
    return baseEnText;
  }

  Future<void> _translateAsync(String key, String englishText) async {
    _translatingSet.add(key);
    
    try {
      final toCode = _translatorCodeMap[_selectedLanguage] ?? 'es';
      final translation = await _translator.translate(englishText, from: 'en', to: toCode);
      
      // Save it to dynamic translation dictionary
      _dynamicTranslations[key] = translation.text;
      
      // Persist the cache
      await _saveDynamicCache();
      
      // Rebuild the UI to instantly display the new phrase!
      notifyListeners();
    } catch (e) {
      debugPrint('Dynamic translation failed for [$key]: $e');
    } finally {
      // Give a tiny buffer before allowing another request for the same key
      Future.delayed(const Duration(seconds: 5), () {
        _translatingSet.remove(key);
      });
    }
  }
}