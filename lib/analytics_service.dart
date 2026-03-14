import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ANALYTICS SERVICE
//  Singleton.  Persists in SharedPreferences — works fully offline,
//  requires zero extra pub packages.
//
//  USAGE IN EVERY PAGE:
//
//    @override void initState() {
//      super.initState();
//      AnalyticsService.instance.startFeatureSession('Home');
//    }
//    @override void dispose() {
//      AnalyticsService.instance.endFeatureSession('Home');
//      super.dispose();
//    }
// ─────────────────────────────────────────────────────────────────────────────

class AnalyticsService extends ChangeNotifier {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  // ── SharedPrefs keys ──────────────────────────────────────
  static const _kOpens   = 'vox_opens';
  static const _kFeature = 'vox_feature_ms';
  static const _kDaily   = 'vox_daily_ms';

  // ── In-memory active timers ───────────────────────────────
  final Map<String, DateTime> _active = {};

  // ── Loaded data ───────────────────────────────────────────
  List<DateTime>   _opens     = [];
  Map<String, int> _featureMs = {};
  Map<String, int> _dailyMs   = {};

  List<DateTime>   get opens     => List.unmodifiable(_opens);
  Map<String, int> get featureMs => Map.unmodifiable(_featureMs);
  Map<String, int> get dailyMs   => Map.unmodifiable(_dailyMs);

  // ── Load all persisted data ───────────────────────────────
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();

    final ro = p.getString(_kOpens);
    if (ro != null) {
      _opens = (jsonDecode(ro) as List)
          .map((s) => DateTime.tryParse(s.toString()) ?? DateTime.now())
          .toList();
    }

    final rf = p.getString(_kFeature);
    if (rf != null) {
      _featureMs = (jsonDecode(rf) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }

    final rd = p.getString(_kDaily);
    if (rd != null) {
      _dailyMs = (jsonDecode(rd) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }

    notifyListeners();
  }

  // ── Record app open ───────────────────────────────────────
  Future<void> recordAppOpen() async {
    _opens.add(DateTime.now());
    _prune();
    await _persist(_kOpens,
        jsonEncode(_opens.map((d) => d.toIso8601String()).toList()));
    notifyListeners();
  }

  // ── Feature session tracking ──────────────────────────────
  void startFeatureSession(String feature) {
    _active[feature] = DateTime.now();
  }

  Future<void> endFeatureSession(String feature) async {
    final start = _active.remove(feature);
    if (start == null) return;
    final ms = DateTime.now().difference(start).inMilliseconds;
    if (ms < 500) return;

    _featureMs[feature] = (_featureMs[feature] ?? 0) + ms;
    final dk = _dayKey(DateTime.now());
    _dailyMs[dk] = (_dailyMs[dk] ?? 0) + ms;

    _prune();
    await _persist(_kFeature, jsonEncode(_featureMs));
    await _persist(_kDaily,   jsonEncode(_dailyMs));
    notifyListeners();
  }

  // ── Computed getters ──────────────────────────────────────
  int get opensThisWeek {
    final mon = _weekStart(DateTime.now());
    return _opens.where((d) => !d.isBefore(mon)).length;
  }

  int get opensToday {
    final today = _dayKey(DateTime.now());
    return _opens.where((d) => _dayKey(d) == today).length;
  }

  int get todayTotalMs => _dailyMs[_dayKey(DateTime.now())] ?? 0;

  String? get mostUsedFeature {
    if (_featureMs.isEmpty) return null;
    return _featureMs.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  List<DayData> dailyDataFor(int n) {
    final now = DateTime.now();
    return List.generate(n, (i) {
      final d = now.subtract(Duration(days: n - 1 - i));
      return DayData(date: d, ms: _dailyMs[_dayKey(d)] ?? 0);
    });
  }

  List<MapEntry<String, int>> get sortedFeatures =>
      _featureMs.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  // ── Helpers ───────────────────────────────────────────────
  Future<void> _persist(String key, String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, value);
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    _opens.removeWhere((d) => d.isBefore(cutoff));
    _dailyMs.removeWhere((k, _) {
      final d = DateTime.tryParse(k);
      return d != null && d.isBefore(cutoff);
    });
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime _weekStart(DateTime d) {
    final mon = d.subtract(Duration(days: d.weekday - 1));
    return DateTime(mon.year, mon.month, mon.day);
  }
}

class DayData {
  final DateTime date;
  final int ms;
  const DayData({required this.date, required this.ms});
}
