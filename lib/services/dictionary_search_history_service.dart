import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DictionarySearchEntry {
  final String word;
  final String langCode;
  final DateTime searchedAt;

  const DictionarySearchEntry({
    required this.word,
    required this.langCode,
    required this.searchedAt,
  });

  Map<String, dynamic> toJson() => {
        'word': word,
        'langCode': langCode,
        'searchedAt': searchedAt.toIso8601String(),
      };

  factory DictionarySearchEntry.fromJson(Map<String, dynamic> json) {
    return DictionarySearchEntry(
      word: json['word'] as String? ?? '',
      langCode: json['langCode'] as String? ?? 'en',
      searchedAt: DateTime.tryParse(json['searchedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Keeps dictionary lookups from the last 7 days on this device.
class DictionarySearchHistoryService {
  DictionarySearchHistoryService._();
  static final DictionarySearchHistoryService instance =
      DictionarySearchHistoryService._();

  static const _storageKey = 'dictionary_search_history_v1';
  static const _retention = Duration(days: 7);

  Future<List<DictionarySearchEntry>> loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(DictionarySearchEntry.fromJson)
          .toList();
      final cutoff = DateTime.now().subtract(_retention);
      final recent = list
          .where((e) => e.searchedAt.isAfter(cutoff) && e.word.isNotEmpty)
          .toList()
        ..sort((a, b) => b.searchedAt.compareTo(a.searchedAt));

      if (recent.length != list.length) {
        await _saveAll(recent);
      }
      return recent;
    } catch (_) {
      return [];
    }
  }

  Future<void> recordSearch({
    required String word,
    required String langCode,
  }) async {
    final normalized = word.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final all = await loadRecent();
    all.removeWhere(
      (e) => e.word.toLowerCase() == normalized && e.langCode == langCode,
    );
    all.insert(
      0,
      DictionarySearchEntry(
        word: normalized,
        langCode: langCode,
        searchedAt: DateTime.now(),
      ),
    );

    final trimmed = all.take(40).toList();
    await _saveAll(trimmed);
  }

  Future<void> _saveAll(List<DictionarySearchEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }
}
