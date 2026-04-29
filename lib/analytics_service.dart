import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ANALYTICS SERVICE
//  Singleton.  Persists in SharedPreferences locally and syncs to Firebase
//  for authenticated users. Works offline with local storage.
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
  static const _kOpens     = 'vox_opens';
  static const _kFeature   = 'vox_feature_ms';
  static const _kDaily     = 'vox_daily_ms';
  static const _kDictWords = 'vox_dict_words';
  static const _kFileOps   = 'vox_file_ops';
  static const _kVoiceCmds = 'vox_voice_cmds';
  static const _kUserPrefs = 'vox_user_prefs';
  static const _kLastSync  = 'vox_last_sync';

  // ── In-memory active timers ───────────────────────────────
  final Map<String, DateTime> _active = {};

  // ── Loaded data ───────────────────────────────────────────
  List<DateTime>     _opens     = [];
  Map<String, int>   _featureMs = {};
  Map<String, int>   _dailyMs   = {};
  Map<String, int>   _dictWords = {}; // word -> lookup count
  Map<String, int>   _fileOps   = {}; // operation -> count
  Map<String, int>   _voiceCmds = {}; // command -> usage count
  Map<String, int>   _apiErrors = {}; // source -> count
  Map<String, int>   _unmatchedCommands = {}; // text -> count
  int                _ttsUsageCount = 0;
  Map<String, dynamic> _userPrefs = {}; // user preferences tracking
  DateTime?          _lastSync;
  
  // Streaks & Goals
  int _dailyGoalMinutes = 30; // Default 30 mins
  int _currentStreak = 0;
  int _bestStreak = 0;
  DateTime? _lastGoalDate; // Last day goal was met

  Timer?             _syncTimer;
  static const int   _analyticsSchemaVersion = 2; // Incremented version

  List<DateTime>     get opens     => List.unmodifiable(_opens);
  Map<String, int>   get featureMs => Map.unmodifiable(_featureMs);
  Map<String, int>   get dailyMs   => Map.unmodifiable(_dailyMs);
  Map<String, int>   get dictWords => Map.unmodifiable(_dictWords);
  Map<String, int>   get fileOps   => Map.unmodifiable(_fileOps);
  Map<String, int>   get voiceCmds => Map.unmodifiable(_voiceCmds);
  Map<String, int>   get apiErrors => Map.unmodifiable(_apiErrors);
  Map<String, int>   get unmatchedCommands => Map.unmodifiable(_unmatchedCommands);
  int                get ttsUsageCount => _ttsUsageCount;
  Map<String, dynamic> get userPrefs => Map.unmodifiable(_userPrefs);
  DateTime?          get lastSync => _lastSync;
  int                get dailyGoalMinutes => _dailyGoalMinutes;
  int                get currentStreak => _currentStreak;
  int                get bestStreak => _bestStreak;
  double             get todayGoalProgress => (todayTotalMs / (1000 * 60 * _dailyGoalMinutes)).clamp(0.0, 1.0);

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

    final dw = p.getString(_kDictWords);
    if (dw != null) {
      _dictWords = (jsonDecode(dw) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }

    final fo = p.getString(_kFileOps);
    if (fo != null) {
      _fileOps = (jsonDecode(fo) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }

    final vc = p.getString(_kVoiceCmds);
    if (vc != null) {
      _voiceCmds = (jsonDecode(vc) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }

    final ae = p.getString('vox_api_errors');
    if (ae != null) {
      _apiErrors = (jsonDecode(ae) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }

    final uc = p.getString('vox_unmatched_cmds');
    if (uc != null) {
      _unmatchedCommands = (jsonDecode(uc) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }

    _ttsUsageCount = p.getInt('vox_tts_usage') ?? 0;

    final up = p.getString(_kUserPrefs);
    if (up != null) {
      _userPrefs = jsonDecode(up) as Map<String, dynamic>;
    }

    final ls = p.getString(_kLastSync);
    if (ls != null) {
      _lastSync = DateTime.tryParse(ls);
    }

    _dailyGoalMinutes = p.getInt('vox_daily_goal_mins') ?? 30;
    _currentStreak = p.getInt('vox_current_streak') ?? 0;
    _bestStreak = p.getInt('vox_best_streak') ?? 0;
    final lgd = p.getString('vox_last_goal_date');
    if (lgd != null) _lastGoalDate = DateTime.tryParse(lgd);

    _calculateStreak();

    _syncTimer ??= Timer.periodic(const Duration(hours: 4), (_) {
        autoSyncIfNeeded();
      });

    // run one immediate sync if there is outstanding data
    autoSyncIfNeeded();

    notifyListeners();
  }

  bool get analyticsEnabled => _userPrefs['analyticsEnabled'] as bool? ?? true;

  Future<void> setAnalyticsEnabled(bool enabled) async {
    _userPrefs['analyticsEnabled'] = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUserPrefs, jsonEncode(_userPrefs));
    notifyListeners();
  }

  // ── Record dictionary word lookup ────────────────────────
  Future<void> recordDictionaryLookup(String word) async {
    final cleanWord = word.toLowerCase().trim();
    if (cleanWord.isEmpty) return;

    _dictWords[cleanWord] = (_dictWords[cleanWord] ?? 0) + 1;
    await _persist(_kDictWords, jsonEncode(_dictWords));
    notifyListeners();
  }

  // ── Record file operation ──────────────────────────────────
  Future<void> recordFileOperation(String operation) async {
    _fileOps[operation] = (_fileOps[operation] ?? 0) + 1;
    await _persist(_kFileOps, jsonEncode(_fileOps));
    notifyListeners();
  }

  // ── Record voice command usage ─────────────────────────────
  Future<void> recordVoiceCommand(String command) async {
    _voiceCmds[command] = (_voiceCmds[command] ?? 0) + 1;
    await _persist(_kVoiceCmds, jsonEncode(_voiceCmds));
    notifyListeners();
  }

  // ── Record API Error ───────────────────────────────────────
  Future<void> recordApiError(String source, String error) async {
    _apiErrors[source] = (_apiErrors[source] ?? 0) + 1;
    await _persist('vox_api_errors', jsonEncode(_apiErrors));
    notifyListeners();
  }

  // ── Record Unmatched Voice Command ────────────────────────
  Future<void> recordUnmatchedCommand(String input) async {
    final cleanInput = input.trim();
    if (cleanInput.isEmpty) return;
    _unmatchedCommands[cleanInput] = (_unmatchedCommands[cleanInput] ?? 0) + 1;
    await _persist('vox_unmatched_cmds', jsonEncode(_unmatchedCommands));
    notifyListeners();
  }

  // ── Record TTS Usage ───────────────────────────────────────
  Future<void> recordTtsUsage() async {
    _ttsUsageCount++;
    final p = await SharedPreferences.getInstance();
    await p.setInt('vox_tts_usage', _ttsUsageCount);
    notifyListeners();
  }

  // ── Record app open ────────────────────────────────────────
  Future<void> recordAppOpen() async {
    _opens.add(DateTime.now());
    await _persist(_kOpens, jsonEncode(_opens.map((d) => d.toIso8601String()).toList()));
    notifyListeners();
  }

  // ── Firebase sync methods ──────────────────────────────────
  Future<void> syncToFirebase({int attempt = 0}) async {
    if (!analyticsEnabled) {
      debugPrint('Analytics sync skipped (opt-out)');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return; // Only sync for authenticated users

    if (attempt > 3) {
      debugPrint('Analytics sync aborted after $attempt attempts');
      return;
    }

    try {
      final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final analyticsDoc = userDoc.collection('analytics').doc('daily_stats');

      // Get today's date key
      final todayKey = _dayKey(DateTime.now());

      // Prepare data to sync
      final syncData = {
        'schemaVersion': _analyticsSchemaVersion,
        'lastSync': FieldValue.serverTimestamp(),
        'totalOpens': _opens.length,
        'totalTimeMs': _dailyMs.values.fold(0, (a, b) => a + b),
        'featureUsage': _featureMs,
        'dailyActivity': _dailyMs,
        'dictionaryLookups': _dictWords,
        'fileOperations': _fileOps,
        'voiceCommands': _voiceCmds,
        'todayOpens': _opens.where((d) => _dayKey(d) == todayKey).length,
        'todayTimeMs': _dailyMs[todayKey] ?? 0,
        'uniqueWords': _dictWords.length,
        'totalDictLookups': _dictWords.values.fold(0, (a, b) => a + b),
        'totalFileOps': _fileOps.values.fold(0, (a, b) => a + b),
        'totalVoiceCmds': _voiceCmds.values.fold(0, (a, b) => a + b),
        'totalApiErrors': _apiErrors.values.fold(0, (a, b) => a + b),
        'totalUnmatched': _unmatchedCommands.values.fold(0, (a, b) => a + b),
        'ttsUsage': _ttsUsageCount,
        'activeDays': _dailyMs.keys.where((k) {
          final d = DateTime.tryParse(k);
          return d != null && d.isAfter(DateTime.now().subtract(const Duration(days: 30)));
        }).length,
      };

      await analyticsDoc.set(syncData, SetOptions(merge: true));

      // Update last sync time
      _lastSync = DateTime.now();
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLastSync, _lastSync!.toIso8601String());

      notifyListeners();
    } catch (e) {
      debugPrint('Analytics sync failed: $e');
      final delay = Duration(seconds: 2 * (attempt + 1));
      await Future.delayed(delay);
      await syncToFirebase(attempt: attempt + 1);
    }
  }

  // ── Check if sync is needed (daily sync) ───────────────────
  bool get needsSync {
    if (_lastSync == null) return true;
    final now = DateTime.now();
    final lastSyncDate = DateTime(_lastSync!.year, _lastSync!.month, _lastSync!.day);
    final today = DateTime(now.year, now.month, now.day);
    return lastSyncDate.isBefore(today);
  }

  // ── Auto-sync if needed ─────────────────────────────────────
  Future<void> autoSyncIfNeeded() async {
    if (needsSync) {
      await syncToFirebase();
    }
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
    
    _checkGoalReached();
    notifyListeners();
  }

  void _checkGoalReached() async {
    final todayKey = _dayKey(DateTime.now());
    final todayMs = _dailyMs[todayKey] ?? 0;
    final goalMs = _dailyGoalMinutes * 60 * 1000;

    if (todayMs >= goalMs && (_lastGoalDate == null || _dayKey(_lastGoalDate!) != todayKey)) {
      _lastGoalDate = DateTime.now();
      _calculateStreak();
      
      final p = await SharedPreferences.getInstance();
      await p.setString('vox_last_goal_date', _lastGoalDate!.toIso8601String());
      await p.setInt('vox_current_streak', _currentStreak);
      await p.setInt('vox_best_streak', _bestStreak);
      
      // Notify user!
      // This would normally call NotificationService, but since we are in a singleton, 
      // we can just notify listeners and let the UI handle the "Goal Reached" animation.
      debugPrint('🎉 Daily Goal Reached! Streak: $_currentStreak');
    }
  }

  void _calculateStreak() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int streak = 0;
    
    // Iterate backwards from yesterday to find consecutive days where goal was met
    for (int i = 0; ; i++) {
      final date = today.subtract(Duration(days: i));
      final key = _dayKey(date);
      final ms = _dailyMs[key] ?? 0;
      final goalMs = _dailyGoalMinutes * 60 * 1000;
      
      if (ms >= goalMs) {
        streak++;
      } else if (i == 0) {
        // Today goal not met yet, streak might be from yesterday
        continue;
      } else {
        break;
      }
    }
    
    _currentStreak = streak;
    if (_currentStreak > _bestStreak) _bestStreak = _currentStreak;
  }

  Future<void> setDailyGoal(int minutes) async {
    _dailyGoalMinutes = minutes;
    final p = await SharedPreferences.getInstance();
    await p.setInt('vox_daily_goal_mins', minutes);
    _calculateStreak();
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

  List<MapEntry<String, int>> get sortedDictWords =>
      _dictWords.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  List<MapEntry<String, int>> get sortedFileOps =>
      _fileOps.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  List<MapEntry<String, int>> get sortedVoiceCmds =>
      _voiceCmds.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  int get totalDictLookups => _dictWords.values.fold(0, (a, b) => a + b);
  int get totalFileOps => _fileOps.values.fold(0, (a, b) => a + b);
  int get totalVoiceCmds => _voiceCmds.values.fold(0, (a, b) => a + b);
  int get uniqueWordsLookedUp => _dictWords.length;
  int get uniqueVoiceCmds => _voiceCmds.length;

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

    // Prune old dictionary words (keep only top 1000 most used)
    if (_dictWords.length > 1000) {
      final sorted = _dictWords.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _dictWords = Map.fromEntries(sorted.take(1000));
    }

    // Prune old voice commands (keep only top 500 most used)
    if (_voiceCmds.length > 500) {
      final sorted = _voiceCmds.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _voiceCmds = Map.fromEntries(sorted.take(500));
    }
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
