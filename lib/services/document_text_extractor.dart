import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

/// Extracts plain text from Office Open XML documents (DOCX, PPTX, etc.).
/// Embedded pictures are skipped — only readable text is returned.
class DocumentTextExtractor {
  DocumentTextExtractor._();

  static final _imageExt = RegExp(
    r'\.(png|jpe?g|gif|bmp|webp|tiff?|emf|wmf|svg|ico)$',
    caseSensitive: false,
  );

  /// DOCX or OOXML-in-zip (some `.doc` saves are zip-based).
  static String extractDocx(List<int> bytes) {
    try {
      final archive = _openZip(bytes);
      final buffer = StringBuffer();

      final parts = _sortedDocxXmlFiles(archive);
      for (final file in parts) {
        final xml = _readXmlEntry(file);
        if (xml == null) continue;
        final text = _extractDocxXml(xml);
        if (text.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.writeln(text);
        }
      }

      var result = _normalize(buffer.toString());
      if (result.isEmpty) {
        result = _extractAllDocxTextRuns(archive);
      }
      return result;
    } catch (e) {
      debugPrint('DocumentTextExtractor DOCX error: $e');
      return '';
    }
  }

  /// Legacy `.doc` or zip-based Word — images are ignored.
  static String extractDoc(List<int> bytes, {String extension = 'doc'}) {
    if (extension == 'docx' || isZipBytes(bytes)) {
      return extractDocx(bytes);
    }
    return extractLegacyBinaryOffice(bytes);
  }

  static String extractPptx(List<int> bytes) {
    try {
      final archive = _openZip(bytes);
      final buffer = StringBuffer();

      final slideFiles = archive.files.where((f) {
        if (!f.isFile || _shouldSkipEntry(f.name)) return false;
        final path = _normPath(f.name);
        return RegExp(r'ppt/slides/slide\d+\.xml$').hasMatch(path);
      }).toList()
        ..sort((a, b) => _slideNumber(a.name).compareTo(_slideNumber(b.name)));

      for (var i = 0; i < slideFiles.length; i++) {
        final xml = _readXmlEntry(slideFiles[i]);
        if (xml == null) continue;
        final slideText = _extractPresentationXml(xml);
        if (slideText.isEmpty) continue;
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.writeln('Slide ${i + 1}');
        buffer.writeln(slideText);
      }

      // Speaker notes (text only — not slide pictures).
      final noteFiles = archive.files.where((f) {
        if (!f.isFile || _shouldSkipEntry(f.name)) return false;
        final path = _normPath(f.name);
        return RegExp(r'ppt/notesslides/notesslide\d+\.xml$').hasMatch(path);
      }).toList()
        ..sort((a, b) => _slideNumber(a.name).compareTo(_slideNumber(b.name)));

      for (final file in noteFiles) {
        final xml = _readXmlEntry(file);
        if (xml == null) continue;
        final notes = _extractPresentationXml(xml);
        if (notes.isEmpty) continue;
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.writeln('Notes ${_slideNumber(file.name)}');
        buffer.writeln(notes);
      }

      if (buffer.isEmpty) {
        return _extractPptxFallback(archive);
      }
      return _normalize(buffer.toString());
    } catch (e) {
      debugPrint('DocumentTextExtractor PPTX error: $e');
      return '';
    }
  }

  static String extractOdp(List<int> bytes) {
    try {
      final archive = _openZip(bytes);
      ArchiveFile? contentFile;
      for (final f in archive.files) {
        if (!f.isFile || _shouldSkipEntry(f.name)) continue;
        final path = _normPath(f.name);
        if (path == 'content.xml' || path.endsWith('/content.xml')) {
          contentFile = f;
          break;
        }
      }
      if (contentFile == null) return '';
      final xml = _readXmlEntry(contentFile);
      if (xml == null) return '';
      return _normalize(_extractPresentationXml(xml));
    } catch (e) {
      debugPrint('DocumentTextExtractor ODP error: $e');
      return '';
    }
  }

  static String extractLegacyBinaryOffice(List<int> bytes) {
    final found = <String>{};
    final buffer = StringBuffer();

    void addIfMeaningful(String value) {
      final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleaned.length < 3) return;
      final letters = RegExp(r'[\p{L}]', unicode: true).allMatches(cleaned).length;
      if (letters < 2) return;
      if (found.add(cleaned)) buffer.writeln(cleaned);
    }

    // UTF-16 LE runs (common in legacy Office binary files).
    final runes = StringBuffer();
    for (var i = 0; i < bytes.length - 1; i += 2) {
      final code = bytes[i] | (bytes[i + 1] << 8);
      if (code >= 32 && code < 0xD800) {
        runes.writeCharCode(code);
      } else {
        if (runes.length >= 4) addIfMeaningful(runes.toString());
        runes.clear();
      }
    }
    if (runes.length >= 4) addIfMeaningful(runes.toString());

    // ASCII runs as a backup.
    final ascii = StringBuffer();
    for (final b in bytes) {
      if (b >= 32 && b <= 126) {
        ascii.writeCharCode(b);
      } else {
        if (ascii.length >= 6) addIfMeaningful(ascii.toString());
        ascii.clear();
      }
    }
    if (ascii.length >= 6) addIfMeaningful(ascii.toString());

    return _normalize(buffer.toString());
  }

  static bool isZipBytes(List<int> bytes) =>
      bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;

  static Archive _openZip(List<int> bytes) =>
      ZipDecoder().decodeBytes(bytes, verify: false);

  static String _normPath(String path) =>
      path.replaceAll('\\', '/').toLowerCase();

  /// Skip embedded images and other binary media — text lives in XML parts only.
  static bool _shouldSkipEntry(String path) {
    final lower = _normPath(path);
    if (lower.contains('/media/')) return true;
    if (lower.contains('/embeddings/')) return true;
    if (_imageExt.hasMatch(lower)) return true;
    return false;
  }

  static bool _isDocxXmlPart(String path) {
    final lower = _normPath(path);
    if (!lower.startsWith('word/') || !lower.endsWith('.xml')) return false;
    if (lower.startsWith('word/media/')) return false;
    return true;
  }

  static bool _isPptxXmlPart(String path) {
    final lower = _normPath(path);
    if (!lower.endsWith('.xml')) return false;
    if (lower.contains('/media/')) return false;
    return lower.contains('ppt/') || lower == 'content.xml';
  }

  static List<ArchiveFile> _sortedDocxXmlFiles(Archive archive) {
    final files = archive.files
        .where((f) => f.isFile && !_shouldSkipEntry(f.name) && _isDocxXmlPart(f.name))
        .toList()
      ..sort((a, b) => _compareDocxParts(a.name, b.name));
    return files;
  }

  static int _compareDocxParts(String a, String b) {
    int rank(String p) {
      final lower = _normPath(p);
      if (lower == 'word/document.xml') return 0;
      if (lower.startsWith('word/header')) return 1;
      if (lower.startsWith('word/footer')) return 2;
      if (lower == 'word/footnotes.xml' || lower == 'word/endnotes.xml') {
        return 3;
      }
      return 4;
    }

    final ra = rank(a);
    final rb = rank(b);
    if (ra != rb) return ra.compareTo(rb);
    return a.compareTo(b);
  }

  static int _slideNumber(String path) {
    final match = RegExp(r'slide(\d+)', caseSensitive: false).firstMatch(path);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
  }

  static String? _readXmlEntry(ArchiveFile file) {
    if (!file.name.toLowerCase().endsWith('.xml')) return null;
    if (file.size > 8 * 1024 * 1024) return null;
    try {
      final raw = file.readBytes();
      if (raw == null || raw.isEmpty) return null;
      return utf8.decode(raw, allowMalformed: true);
    } catch (e) {
      debugPrint('DocumentTextExtractor: skip ${file.name}: $e');
      return null;
    }
  }

  static String _extractAllDocxTextRuns(Archive archive) {
    final buffer = StringBuffer();
    for (final file in _sortedDocxXmlFiles(archive)) {
      final xml = _readXmlEntry(file);
      if (xml == null) continue;
      final runs = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);
      for (final m in runs.allMatches(xml)) {
        final t = _decodeXmlEntities(m.group(1) ?? '');
        if (t.isNotEmpty) buffer.write('$t ');
      }
    }
    return _normalize(buffer.toString());
  }

  static String _extractDocxXml(String xml) {
    final buffer = StringBuffer();

    final paragraphPattern = RegExp(r'<w:p\b[^>]*>(.*?)</w:p>', dotAll: true);
    for (final para in paragraphPattern.allMatches(xml)) {
      final line = _collectDocxInlineText(para.group(1) ?? '');
      if (line.isNotEmpty) buffer.writeln(line);
    }

    final textBoxPattern =
        RegExp(r'<w:txbxContent>(.*?)</w:txbxContent>', dotAll: true);
    for (final box in textBoxPattern.allMatches(xml)) {
      for (final para in paragraphPattern.allMatches(box.group(1) ?? '')) {
        final line = _collectDocxInlineText(para.group(1) ?? '');
        if (line.isNotEmpty) buffer.writeln(line);
      }
    }

    // Text inside drawings / alternate content blocks (still typed text, not pics).
    final drawingTextPattern = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);
    if (buffer.isEmpty) {
      for (final m in drawingTextPattern.allMatches(xml)) {
        final t = _decodeXmlEntities(m.group(1) ?? '');
        if (t.isNotEmpty) buffer.write('$t ');
      }
    }

    return buffer.toString().trim();
  }

  static String _collectDocxInlineText(String paraXml) {
    final buffer = StringBuffer();
    final tokenPattern = RegExp(
      r'<w:tab\b|<w:br\b|<w:cr\b|<w:t[^>]*>(.*?)</w:t>',
      dotAll: true,
    );
    for (final m in tokenPattern.allMatches(paraXml)) {
      final text = m.group(1);
      if (text != null) {
        buffer.write(_decodeXmlEntities(text));
      } else {
        buffer.write(' ');
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _extractPresentationXml(String xml) {
    final patterns = [
      RegExp(r'<a:t[^>]*>(.*?)</a:t>', dotAll: true),
      RegExp(r'<a14:t[^>]*>(.*?)</a14:t>', dotAll: true),
      RegExp(r'<p:t[^>]*>(.*?)</p:t>', dotAll: true),
      RegExp(r'<text:span[^>]*>(.*?)</text:span>', dotAll: true),
      RegExp(r'<text:p[^>]*>(.*?)</text:p>', dotAll: true),
      RegExp(r'<(?:(?:a|p|a14|p14):)?t[^>]*>(.*?)</(?:(?:a|p|a14|p14):)?t>', dotAll: true),
    ];

    final parts = <String>[];
    for (final pattern in patterns) {
      for (final m in pattern.allMatches(xml)) {
        final t = _decodeXmlEntities(m.group(1) ?? '');
        if (t.isNotEmpty) parts.add(t);
      }
    }
    return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _extractPptxFallback(Archive archive) {
    final buffer = StringBuffer();

    final xmlFiles = archive.files
        .where((f) => f.isFile && !_shouldSkipEntry(f.name) && _isPptxXmlPart(f.name))
        .toList()
      ..sort((a, b) {
        final sa = _slideNumber(a.name);
        final sb = _slideNumber(b.name);
        if (sa != sb) return sa.compareTo(sb);
        return a.name.compareTo(b.name);
      });

    var lastSlide = -1;
    for (final file in xmlFiles) {
      final xml = _readXmlEntry(file);
      if (xml == null) continue;
      final text = _extractPresentationXml(xml);
      if (text.isEmpty) continue;

      final slideNum = _slideNumber(file.name);
      if (slideNum > 0 && slideNum != lastSlide) {
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.writeln('Slide $slideNum');
        lastSlide = slideNum;
      } else if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.writeln(text);
    }
    return _normalize(buffer.toString());
  }

  static String _decodeXmlEntities(String raw) {
    var text = raw;
    text = text.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    text = text
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text;
  }

  static String _normalize(String text) =>
      text.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');
}
