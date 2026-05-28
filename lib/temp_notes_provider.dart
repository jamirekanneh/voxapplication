import 'package:flutter/material.dart';

class TempNote {
  final String id;
  final String title;
  final String content;
  final String? audioUrl;
  final String? audioPath;
  final int? durationSeconds;
  final DateTime createdAt;

  TempNote({
    required this.id,
    required this.title,
    required this.content,
    this.audioUrl,
    this.audioPath,
    this.durationSeconds,
    required this.createdAt,
  });
}

class TempNotesProvider extends ChangeNotifier {
  final List<TempNote> _notes = [];

  List<TempNote> get notes => List.unmodifiable(_notes);

  void add(
    String title,
    String content, {
    String? audioUrl,
    String? audioPath,
    int? durationSeconds,
  }) {
    _notes.insert(
      0,
      TempNote(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title.isNotEmpty ? title : 'Note',
        content: content,
        audioUrl: audioUrl,
        audioPath: audioPath,
        durationSeconds: durationSeconds,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void update(
    String id,
    String title,
    String content, {
    String? audioUrl,
    String? audioPath,
    int? durationSeconds,
  }) {
    final index = _notes.indexWhere((n) => n.id == id);
    if (index != -1) {
      final existing = _notes[index];
      _notes[index] = TempNote(
        id: id,
        title: title.isNotEmpty ? title : 'Note',
        content: content,
        audioUrl: audioUrl ?? existing.audioUrl,
        audioPath: audioPath ?? existing.audioPath,
        durationSeconds: durationSeconds ?? existing.durationSeconds,
        createdAt: existing.createdAt,
      );
      notifyListeners();
    }
  }

  void remove(String id) {
    _notes.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  void clear() {
    _notes.clear();
    notifyListeners();
  }
}
