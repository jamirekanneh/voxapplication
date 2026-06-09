import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../temp_library_provider.dart';

/// A character range pinned by the voice "highlight" command.
class HighlightRange {
  final int start;
  final int end;

  const HighlightRange(this.start, this.end);

  Map<String, int> toMap() => {'start': start, 'end': end};

  static HighlightRange? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final start = LibraryHighlightService._asOffset(raw['start']);
    final end = LibraryHighlightService._asOffset(raw['end']);
    if (start == null || end == null || end <= start) return null;
    return HighlightRange(start, end);
  }

  @override
  bool operator ==(Object other) =>
      other is HighlightRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Persists read-aloud sentence highlights on library documents.
class LibraryHighlightService {
  LibraryHighlightService._();

  static int? _asOffset(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }

  static List<HighlightRange> fromLibraryData(Map<String, dynamic> data) {
    final ranges = <HighlightRange>[];
    final seen = <String>{};

    void add(HighlightRange? range) {
      if (range == null) return;
      final key = '${range.start}:${range.end}';
      if (seen.add(key)) ranges.add(range);
    }

    final raw = data['highlights'];
    if (raw is List) {
      for (final item in raw) {
        add(HighlightRange.fromMap(item));
      }
    }

    final legacyStart = _asOffset(data['highlightStart']);
    final legacyEnd = _asOffset(data['highlightEnd']);
    if (legacyStart != null && legacyEnd != null && legacyEnd > legacyStart) {
      add(HighlightRange(legacyStart, legacyEnd));
    }

    ranges.sort((a, b) => a.start.compareTo(b.start));
    return ranges;
  }

  static List<HighlightRange> _sortedUnique(List<HighlightRange> ranges) {
    final seen = <String>{};
    final out = <HighlightRange>[];
    for (final r in ranges) {
      if (r.end <= r.start) continue;
      final key = '${r.start}:${r.end}';
      if (seen.add(key)) out.add(r);
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  /// Appends a highlighted sentence range (no overwrite of prior pins).
  static Future<void> addHighlight({
    required BuildContext context,
    required String fileName,
    required int start,
    required int end,
    String? libraryDocId,
    bool guestLibrary = false,
    List<HighlightRange> existing = const [],
  }) async {
    if (start < 0 || end <= start) return;

    final next = _sortedUnique([
      ...existing,
      HighlightRange(start, end),
    ]);

    try {
      if (guestLibrary && libraryDocId != null) {
        context.read<TempLibraryProvider>().addHighlight(
              id: libraryDocId,
              start: start,
              end: end,
            );
        return;
      }

      if (libraryDocId == null || libraryDocId.isEmpty) return;

      await FirebaseFirestore.instance.collection('library').doc(libraryDocId).set(
        {
          'highlights': next.map((e) => e.toMap()).toList(),
          'highlightStart': start,
          'highlightEnd': end,
          'highlightUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('LibraryHighlightService add failed for "$fileName": $e');
    }
  }
}
