import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────
//  ACTION TYPES
// ─────────────────────────────────────────────
enum CommandActionType {
  navigateHome,
  navigateNotes,
  navigateMenu,
  navigateDictionary,
  ttsPlay,
  ttsPause,
  ttsStop,
  ttsSpeedUp,
  ttsSlowDown,
  searchNotes,
  openNote,
  macroSequence,
}

extension CommandActionTypeLabel on CommandActionType {
  String get displayName {
    switch (this) {
      case CommandActionType.navigateHome:
        return 'Go to Home';
      case CommandActionType.navigateNotes:
        return 'Go to Notes';
      case CommandActionType.navigateMenu:
        return 'Go to Menu';
      case CommandActionType.navigateDictionary:
        return 'Go to Dictionary';
      case CommandActionType.ttsPlay:
        return 'Play / Resume Reading';
      case CommandActionType.ttsPause:
        return 'Pause Reading';
      case CommandActionType.ttsStop:
        return 'Stop Reading';
      case CommandActionType.ttsSpeedUp:
        return 'Speed Up Reading';
      case CommandActionType.ttsSlowDown:
        return 'Slow Down Reading';
      case CommandActionType.searchNotes:
        return 'Search Notes';
      case CommandActionType.openNote:
        return 'Open Specific Note';
      case CommandActionType.macroSequence:
        return 'Run Macro Sequence';
    }
  }

  IconData get icon {
    switch (this) {
      case CommandActionType.navigateHome:
        return Icons.home_outlined;
      case CommandActionType.navigateNotes:
        return Icons.note_alt_outlined;
      case CommandActionType.navigateMenu:
        return Icons.menu;
      case CommandActionType.navigateDictionary:
        return Icons.book_outlined;
      case CommandActionType.ttsPlay:
        return Icons.play_arrow_outlined;
      case CommandActionType.ttsPause:
        return Icons.pause_outlined;
      case CommandActionType.ttsStop:
        return Icons.stop_outlined;
      case CommandActionType.ttsSpeedUp:
        return Icons.fast_forward_outlined;
      case CommandActionType.ttsSlowDown:
        return Icons.fast_rewind_outlined;
      case CommandActionType.searchNotes:
        return Icons.search_outlined;
      case CommandActionType.openNote:
        return Icons.file_open_outlined;
      case CommandActionType.macroSequence:
        return Icons.timeline_rounded;
    }
  }

  bool get requiresParameter {
    return this == CommandActionType.searchNotes ||
        this == CommandActionType.openNote ||
        this == CommandActionType.macroSequence;
  }

  String get parameterHint {
    switch (this) {
      case CommandActionType.searchNotes:
        return 'Keyword to search for';
      case CommandActionType.openNote:
        return 'Note name to open';
      case CommandActionType.macroSequence:
        return 'Macro steps (one per line, e.g. open notes)';
      default:
        return '';
    }
  }
}

// ─────────────────────────────────────────────
//  COMMAND MODEL
// ─────────────────────────────────────────────
class CustomCommand {
  final String id;
  final String phrase;
  final CommandActionType action;
  final String? parameter;
  final bool isEnabled;

  const CustomCommand({
    required this.id,
    required this.phrase,
    required this.action,
    this.parameter,
    this.isEnabled = true,
  });

  CustomCommand copyWith({
    String? phrase,
    CommandActionType? action,
    String? parameter,
    bool? isEnabled,
  }) {
    return CustomCommand(
      id: id,
      phrase: phrase ?? this.phrase,
      action: action ?? this.action,
      parameter: parameter ?? this.parameter,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phrase': phrase,
        'action': action.name,
        'parameter': parameter,
        'isEnabled': isEnabled,
      };

  factory CustomCommand.fromJson(Map<String, dynamic> json) {
    return CustomCommand(
      id: json['id'] as String,
      phrase: json['phrase'] as String,
      action: CommandActionType.values.firstWhere(
        (e) => e.name == json['action'],
        orElse: () => CommandActionType.navigateHome,
      ),
      parameter: json['parameter'] as String?,
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }
}

// ─────────────────────────────────────────────
//  PROVIDER
// ─────────────────────────────────────────────
class CustomCommandsProvider extends ChangeNotifier {
  static const _prefsKey = 'custom_commands';
  static const _feedbackKey = 'commands_voice_feedback';

  List<CustomCommand> _commands = [];
  bool _voiceFeedbackEnabled = true;
  String? _currentUserId;

  // FIX: track whether _load() has completed so GlobalSttWrapper
  // doesn't call match() against an empty list on first launch.
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  List<CustomCommand> get commands => List.unmodifiable(_commands);
  List<CustomCommand> get enabledCommands =>
      _commands.where((c) => c.isEnabled).toList();
  bool get voiceFeedbackEnabled => _voiceFeedbackEnabled;

  CustomCommandsProvider() {
    _load();
  }

  // ── Persistence ──────────────────────────────
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _voiceFeedbackEnabled = prefs.getBool(_feedbackKey) ?? true;
    // For initial load, don't load commands - wait for loadCommandsForUser
    _isLoaded = true;
    notifyListeners();
  }

  // ── CRUD ─────────────────────────────────────
  Future<void> addCommand(CustomCommand command) async {
    _commands.add(command);
    notifyListeners();
    if (_currentUserId != null) {
      await _saveForUser(_currentUserId!);
    }
  }

  Future<void> updateCommand(CustomCommand updated) async {
    final idx = _commands.indexWhere((c) => c.id == updated.id);
    if (idx != -1) {
      _commands[idx] = updated;
      notifyListeners();
      if (_currentUserId != null) {
        await _saveForUser(_currentUserId!);
      }
    }
  }

  Future<void> deleteCommand(String id) async {
    _commands.removeWhere((c) => c.id == id);
    notifyListeners();
    if (_currentUserId != null) {
      await _saveForUser(_currentUserId!);
    }
  }

  Future<void> toggleCommand(String id) async {
    final idx = _commands.indexWhere((c) => c.id == id);
    if (idx != -1) {
      _commands[idx] = _commands[idx].copyWith(
        isEnabled: !_commands[idx].isEnabled,
      );
      notifyListeners();
      if (_currentUserId != null) {
        await _saveForUser(_currentUserId!);
      }
    }
  }

  Future<void> setVoiceFeedback(bool enabled) async {
    _voiceFeedbackEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_feedbackKey, enabled);
  }

  // ── Load commands for specific user ──────────────────
  Future<void> loadCommandsForUser(String uid) async {
    _currentUserId = uid;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        // Load from Firestore for authenticated users
        final snapshot = await FirebaseFirestore.instance
            .collection('custom_commands')
            .where('userId', isEqualTo: uid)
            .get();

        _commands = snapshot.docs
            .map((doc) => CustomCommand.fromJson(doc.data()))
            .toList();
      } else {
        // Load from SharedPreferences for anonymous users
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('${_prefsKey}_$uid');
        if (raw != null) {
          try {
            final list = jsonDecode(raw) as List;
            _commands = list
                .map((e) => CustomCommand.fromJson(e as Map<String, dynamic>))
                .toList();
          } catch (_) {
            _commands = [];
          }
        } else {
          _commands = [];
        }
      }
      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading commands for user $uid: $e');
      _commands = [];
      _isLoaded = true;
      notifyListeners();
    }
  }

  // ── Save commands for specific user ──────────────────
  Future<void> _saveForUser(String uid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      // Save to Firestore for authenticated users
      final batch = FirebaseFirestore.instance.batch();
      
      // Delete existing commands
      final existing = await FirebaseFirestore.instance
          .collection('custom_commands')
          .where('userId', isEqualTo: uid)
          .get();
      
      for (final doc in existing.docs) {
        batch.delete(doc.reference);
      }
      
      // Add new commands
      for (final command in _commands) {
        final docRef = FirebaseFirestore.instance.collection('custom_commands').doc();
        batch.set(docRef, {
          ...command.toJson(),
          'userId': uid,
        });
      }
      
      await batch.commit();
    } else {
      // Save to SharedPreferences for anonymous users
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '${_prefsKey}_$uid',
        jsonEncode(_commands.map((c) => c.toJson()).toList()),
      );
    }
  }

  // ── Matching ──────────────────────────────────
  /// Returns the best matching command for [spokenText], or null if none found.
  CustomCommand? match(String spokenText) {
    final input = _normalize(spokenText);
    CustomCommand? best;
    double bestScore = 0.4; // minimum threshold

    for (final cmd in enabledCommands) {
      final score = _score(input, _normalize(cmd.phrase));
      if (score > bestScore) {
        bestScore = score;
        best = cmd;
      }
    }
    return best;
  }

  String _normalize(String text) =>
      text.toLowerCase().trim().replaceAll(RegExp(r'[^\w\s]'), '');

  CustomCommand? findByPhrase(String phrase) {
    final normalized = _normalize(phrase);
    for (final cmd in enabledCommands) {
      if (_normalize(cmd.phrase) == normalized) return cmd;
    }
    return null;
  }

  double _score(String input, String phrase) {
    if (input == phrase) return 1.0;
    if (input.contains(phrase)) return 0.95;
    if (phrase.contains(input)) return 0.85;

    // Word overlap
    final inputWords = input.split(' ').toSet();
    final phraseWords = phrase.split(' ').toSet();
    final overlap = inputWords.intersection(phraseWords).length;
    final total = phraseWords.length;
    if (total == 0) return 0.0;
    return overlap / total;
  }
}