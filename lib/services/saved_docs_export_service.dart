import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'saved_docs_service.dart';

/// Exports saved docs to a ZIP on device storage.
class SavedDocsExportService {
  SavedDocsExportService._();

  static String _sanitizeFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[^\w\s\-.]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    return cleaned.isEmpty ? 'untitled' : cleaned.substring(0, cleaned.length.clamp(0, 80));
  }

  static String _entryText(SavedDocEntry entry) {
    switch (entry.type) {
      case SavedDocsService.typeSummary:
      case SavedDocsService.typeNote:
        return entry.data['content'] as String? ?? '';
      case SavedDocsService.typeQa:
        final questions = entry.data['questions'] as List<dynamic>? ?? [];
        final buffer = StringBuffer();
        buffer.writeln('${entry.title}\nSource: ${entry.source}\n');
        for (var i = 0; i < questions.length; i++) {
          final m = questions[i] as Map<String, dynamic>;
          buffer.writeln('Q${i + 1}: ${m['question'] ?? ''}');
          buffer.writeln('A: ${m['answer'] ?? ''}\n');
        }
        return buffer.toString();
      default:
        return '';
    }
  }

  static String _extensionFor(SavedDocEntry entry) {
    return entry.type == SavedDocsService.typeQa ? 'txt' : 'txt';
  }

  static String _typePrefix(SavedDocEntry entry) {
    switch (entry.type) {
      case SavedDocsService.typeSummary:
        return 'Summary';
      case SavedDocsService.typeNote:
        return 'Note';
      default:
        return 'QA';
    }
  }

  /// Returns path to the created ZIP file, or null on failure.
  static Future<String?> exportToZip(
    BuildContext context,
    List<SavedDocEntry> entries,
  ) async {
    if (entries.isEmpty) return null;

    try {
      final archive = Archive();
      final usedNames = <String>{};

      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final body = _entryText(entry);
        if (body.trim().isEmpty) continue;

        var baseName =
            '${i + 1}_${_typePrefix(entry)}_${_sanitizeFileName(entry.title)}';
        while (usedNames.contains(baseName)) {
          baseName = '${baseName}_$i';
        }
        usedNames.add(baseName);

        final fileName = '$baseName.${_extensionFor(entry)}';
        final bytes = utf8.encode(body);
        archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
      }

      if (archive.files.isEmpty) return null;

      final zipBytes = ZipEncoder().encode(archive);

      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
        dir ??= await getApplicationDocumentsDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final zipPath = '${dir.path}/vox_saved_docs_$stamp.zip';
      await File(zipPath).writeAsBytes(zipBytes);
      return zipPath;
    } catch (e) {
      debugPrint('SavedDocsExportService: $e');
      return null;
    }
  }
}
