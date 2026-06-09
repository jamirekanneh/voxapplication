import 'package:flutter/material.dart';

import 'services/library_highlight_service.dart';

class TempLibraryItem {
  final String id;
  final String fileName;
  final String fileType;
  final String content;
  final int? highlightStart;
  final int? highlightEnd;
  final List<HighlightRange> highlights;

  TempLibraryItem({
    required this.id,
    required this.fileName,
    required this.fileType,
    required this.content,
    this.highlightStart,
    this.highlightEnd,
    List<HighlightRange>? highlights,
  }) : highlights = highlights ?? const [];

  TempLibraryItem copyWith({
    int? highlightStart,
    int? highlightEnd,
    List<HighlightRange>? highlights,
  }) {
    return TempLibraryItem(
      id: id,
      fileName: fileName,
      fileType: fileType,
      content: content,
      highlightStart: highlightStart ?? this.highlightStart,
      highlightEnd: highlightEnd ?? this.highlightEnd,
      highlights: highlights ?? this.highlights,
    );
  }
}

class TempLibraryProvider extends ChangeNotifier {
  final List<TempLibraryItem> _items = [];

  List<TempLibraryItem> get items => List.unmodifiable(_items);

  void add(TempLibraryItem item) {
    _items.insert(0, item); // newest first
    notifyListeners();
  }

  void remove(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  void addHighlight({
    required String id,
    required int start,
    required int end,
  }) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final item = _items[index];
    final range = HighlightRange(start, end);
    if (item.highlights.contains(range)) return;
    final next = [...item.highlights, range]
      ..sort((a, b) => a.start.compareTo(b.start));
    _items[index] = item.copyWith(
      highlightStart: start,
      highlightEnd: end,
      highlights: next,
    );
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}