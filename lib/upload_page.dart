import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive.dart';
import 'temp_library_provider.dart';
import 'language_provider.dart';
import 'tts_service.dart';
import 'reader_page.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  bool _isUploading = false;
  String _statusMessage = 'Uploading...';

  String? _resolvedUid;
  bool _resolvedIsGuest = true;
  bool _resolveAttempted = false;

  // ─────────────────────────────────────────────
  //  RESOLVE USER
  // ─────────────────────────────────────────────
  Future<void> _resolveUser() async {
    if (_resolveAttempted) return;
    _resolveAttempted = true;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _resolvedIsGuest = true;
      _resolvedUid = null;
      return;
    }

    if (!user.isAnonymous) {
      _resolvedIsGuest = false;
      _resolvedUid = user.uid;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final hasProfile = prefs.getBool('hasProfile') ?? false;

    if (!hasProfile) {
      _resolvedIsGuest = true;
      _resolvedUid = null;
      return;
    }

    final uidDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (uidDoc.exists) {
      _resolvedIsGuest = false;
      _resolvedUid = user.uid;
      return;
    }

    final savedEmail = prefs.getString('userEmail') ?? '';
    if (savedEmail.isNotEmpty) {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: savedEmail)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        _resolvedIsGuest = false;
        _resolvedUid = query.docs.first.id;
        return;
      }
    }

    _resolvedIsGuest = true;
    _resolvedUid = null;
  }

  Future<void> _requestPermissionsIfNeeded() async {
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) await Permission.microphone.request();
  }

  // ─────────────────────────────────────────────
  //  PICK & UPLOAD
  // ─────────────────────────────────────────────
  Future<void> _pickAnyFile() async {
    await _requestPermissionsIfNeeded();
    await _resolveUser();

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null) return;

    setState(() {
      _isUploading = true;
      _statusMessage = 'Reading file...';
    });

    final file = result.files.first;
    final String fileName = file.name;
    final String extension = (file.extension ?? 'file').toLowerCase();

    if (file.size > 200 * 1024 * 1024) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('File is too large. Maximum size is 200MB.'),
          backgroundColor: Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    String fileContent = '';

    try {
      if (extension == 'txt' && file.bytes != null) {
        fileContent = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (extension == 'pdf' && file.bytes != null) {
        setState(() => _statusMessage = 'Extracting PDF text...');
        fileContent = await _extractPdfText(file.bytes!);
      } else if ((extension == 'ppt' || extension == 'pptx') &&
          file.bytes != null) {
        setState(() => _statusMessage = 'Extracting presentation text...');
        // FIX: use archive-based extraction for proper ZIP handling
        fileContent = extension == 'pptx'
            ? _extractPptxTextFromZip(file.bytes!)
            : _extractPlainText(file.bytes!);
      } else if ((extension == 'docx' || extension == 'doc') &&
          file.bytes != null) {
        setState(() => _statusMessage = 'Extracting document text...');
        // FIX: use archive-based extraction for proper ZIP handling
        fileContent = extension == 'docx'
            ? _extractDocxTextFromZip(file.bytes!)
            : _extractPlainText(file.bytes!);
      } else if ((extension == 'md' ||
              extension == 'rtf' ||
              extension == 'csv' ||
              extension == 'epub') &&
          file.bytes != null) {
        setState(() => _statusMessage = 'Reading text file...');
        fileContent = _extractPlainText(file.bytes!);
      } else if ((extension == 'xlsx' ||
              extension == 'xls' ||
              extension == 'odt' ||
              extension == 'odp') &&
          file.bytes != null) {
        setState(() => _statusMessage = 'Extracting file text...');
        fileContent = _extractXmlBasedText(file.bytes!);
      } else if (file.bytes != null) {
        setState(() => _statusMessage = 'Reading file...');
        fileContent = _extractPlainText(file.bytes!);
      }

      fileContent = fileContent.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');

      debugPrint('📄 Extracted ${fileContent.length} chars from $fileName ($extension)');

      // ── Save to correct location ──────────────────────
      if (_resolvedIsGuest) {
        setState(() => _statusMessage = 'Adding to temporary library...');
        final tempProvider = context.read<TempLibraryProvider>();
        tempProvider.add(TempLibraryItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          fileName: fileName,
          fileType: extension,
          content: fileContent,
        ));
      } else {
        setState(() => _statusMessage = 'Saving to library...');
        await FirebaseFirestore.instance.collection('library').add({
          'fileName': fileName,
          'fileType': extension,
          'userId': _resolvedUid,
          'content': fileContent,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        setState(() => _isUploading = false);

        SemanticsService.announce(
          'File uploaded. Reading started.',
          TextDirection.ltr,
        );

        final snackMsg = _resolvedIsGuest
            ? '"$fileName" added temporarily. Create an account to save it.'
            : fileContent.isNotEmpty
                ? '"$fileName" uploaded & reading started!'
                : '"$fileName" saved — text could not be extracted from this format.';

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(snackMsg),
          backgroundColor: const Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
        ));

        if (fileContent.isNotEmpty) {
          final locale = context.read<LanguageProvider>().ttsLocale;
          final ttsService = context.read<TtsService>();
          final langProvider = context.read<LanguageProvider>();
          final nav = Navigator.of(context);
          nav.pushReplacement(
            MaterialPageRoute(
              builder: (_) => MultiProvider(
                providers: [
                  ChangeNotifierProvider.value(value: ttsService),
                  ChangeNotifierProvider.value(value: langProvider),
                ],
                child: ReaderPage(
                  title: fileName,
                  content: fileContent,
                  locale: locale,
                ),
              ),
            ),
          );
        } else {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Upload failed. Please try again.'),
          backgroundColor: Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ─────────────────────────────────────────────
  //  TEXT EXTRACTORS
  // ─────────────────────────────────────────────

  Future<String> _extractPdfText(List<int> bytes) async {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final StringBuffer buffer = StringBuffer();
      for (int i = 0; i < document.pages.count; i++) {
        buffer.writeln(
            extractor.extractText(startPageIndex: i, endPageIndex: i));
      }
      document.dispose();
      return buffer.toString();
    } catch (e) {
      debugPrint('PDF extraction error: $e');
      return '';
    }
  }

  // FIX: DOCX is a ZIP — unzip it first, then parse word/document.xml
  String _extractDocxTextFromZip(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final docFile = archive.findFile('word/document.xml');
      if (docFile == null) {
        debugPrint('DOCX: word/document.xml not found in archive');
        return '';
      }
      final xml = utf8.decode(docFile.content as List<int>, allowMalformed: true);
      final regex = RegExp(r'<w:t[^>]*>(.*?)<\/w:t>', dotAll: true);
      final buffer = StringBuffer();
      for (final m in regex.allMatches(xml)) {
        final text = m.group(1) ?? '';
        if (text.isNotEmpty) buffer.write('$text ');
      }
      // Preserve paragraph breaks
      final paraRegex = RegExp(r'<w:p[ >]', dotAll: true);
      final withBreaks = xml.replaceAll(paraRegex, '\n<w:p ');
      final paraBuffer = StringBuffer();
      for (final m in regex.allMatches(withBreaks)) {
        paraBuffer.write(m.group(1) ?? '');
      }
      // Use the paragraph-aware version if it has content
      final result = paraBuffer.toString().trim();
      return result.isNotEmpty ? result : buffer.toString().trim();
    } catch (e) {
      debugPrint('DOCX ZIP extraction error: $e');
      return '';
    }
  }

  // FIX: PPTX is also a ZIP — unzip and parse all slide XML files
  String _extractPptxTextFromZip(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final buffer = StringBuffer();
      final slideRegex = RegExp(r'^ppt/slides/slide\d+\.xml$');
      // Sort slide files so they appear in order
      final slideFiles = archive.files
          .where((f) => slideRegex.hasMatch(f.name))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      final textRegex = RegExp(r'<a:t[^>]*>(.*?)<\/a:t>', dotAll: true);

      for (final slideFile in slideFiles) {
        final xml = utf8.decode(slideFile.content as List<int>, allowMalformed: true);
        String prev = '';
        for (final m in textRegex.allMatches(xml)) {
          final text = m.group(1)?.trim() ?? '';
          if (text.isNotEmpty && text != prev) {
            buffer.write('$text ');
            prev = text;
          }
        }
        buffer.write('\n'); // separate slides
      }
      return buffer.toString().trim();
    } catch (e) {
      debugPrint('PPTX ZIP extraction error: $e');
      return '';
    }
  }

  String _extractPlainText(List<int> bytes) {
    try {
      String raw = utf8.decode(bytes, allowMalformed: true);
      raw = raw.replaceAll(RegExp(r'<[^>]+>'), ' ');
      raw = raw.replaceAll(RegExp(r'[ \t]+'), ' ');
      raw = raw.replaceAll(RegExp(r'\n{3,}'), '\n\n');
      return raw.trim();
    } catch (e) {
      debugPrint('Plain text extraction error: $e');
      return '';
    }
  }

  String _extractXmlBasedText(List<int> bytes) {
    try {
      // Try ZIP-based first (xlsx, odt, odp are ZIP formats)
      try {
        final archive = ZipDecoder().decodeBytes(bytes);
        final buffer = StringBuffer();
        final textRegex = RegExp(
          r'<(?:text:p|text:span|t|a:t|c)[^>]*>(.*?)<\/(?:text:p|text:span|t|a:t|c)>',
          dotAll: true,
        );
        for (final file in archive.files) {
          if (file.name.endsWith('.xml')) {
            final xml = utf8.decode(file.content as List<int>, allowMalformed: true);
            for (final m in textRegex.allMatches(xml)) {
              final text = m.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
              if (text.isNotEmpty) buffer.write('$text ');
            }
          }
        }
        final result = buffer.toString().trim();
        if (result.isNotEmpty) return result;
      } catch (_) {
        // Not a ZIP, fall through to raw parse
      }
      // Fallback: raw XML parse
      final raw = utf8.decode(bytes, allowMalformed: true);
      final regex = RegExp(
        r'<(?:text:p|text:span|t|a:t|c)[^>]*>(.*?)<\/(?:text:p|text:span|t|a:t|c)>',
        dotAll: true,
      );
      final buffer = StringBuffer();
      for (final m in regex.allMatches(raw)) {
        final text = m.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
        if (text.isNotEmpty) buffer.write('$text ');
      }
      return buffer.toString().trim();
    } catch (e) {
      debugPrint('XML-based extraction error: $e');
      return '';
    }
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      appBar: AppBar(
        title: const Text('Upload Files',
            style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Center(
        child: _isUploading
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.black),
                  const SizedBox(height: 16),
                  Text(_statusMessage,
                      style: const TextStyle(color: Colors.black54)),
                ],
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.drive_folder_upload,
                        size: 80, color: Colors.black54),
                    const SizedBox(height: 20),
                    const Text(
                      'Select any file — PDF, Word, PPT, TXT, Excel and more',
                      style: TextStyle(color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Reading will start automatically after upload',
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),

                    FutureBuilder<bool>(
                      future: _isGuestAsync(),
                      builder: (context, snap) {
                        if (snap.data != true) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.only(top: 20),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.black.withOpacity(0.1)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.black54, size: 18),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "You're browsing as a guest. Files will only be available until you close the app.",
                                  style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                      height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 30),
                    Semantics(
                      label: 'Choose a file to upload and read aloud',
                      child: ElevatedButton(
                        onPressed: _pickAnyFile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          minimumSize: const Size(200, 56),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 40, vertical: 15),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                        child: const Text(
                          'CHOOSE FILE',
                          style: TextStyle(
                              color: Color(0xFFF3E5AB), fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<bool> _isGuestAsync() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return true;
    if (!user.isAnonymous) return false;
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('hasProfile') ?? false);
  }
}