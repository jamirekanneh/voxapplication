import 'package:flutter/material.dart';

class TempNote {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;

  TempNote({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
  });
}

class TempNotesProvider extends ChangeNotifier {
  final List<TempNote> _notes = [];

  List<TempNote> get notes => List.unmodifiable(_notes);

  void add(String title, String content) {
    _notes.insert(0, TempNote(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title.isNotEmpty ? title : 'Note',
      content: content,
      createdAt: DateTime.now(),
    ));
    notifyListeners();
  }

  void update(String id, String title, String content) {
    final index = _notes.indexWhere((n) => n.id == id);
    if (index != -1) {
      _notes[index] = TempNote(
        id: id,
        title: title.isNotEmpty ? title : 'Note',
        content: content,
        createdAt: _notes[index].createdAt, // Preserve original timestamp
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