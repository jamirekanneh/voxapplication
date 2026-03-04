import 'package:flutter/material.dart';

class TempLibraryItem {
  final String id;
  final String fileName;
  final String fileType;
  final String content;

  TempLibraryItem({
    required this.id,
    required this.fileName,
    required this.fileType,
    required this.content,
  });
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

  void clear() {
    _items.clear();
    notifyListeners();
  }
}