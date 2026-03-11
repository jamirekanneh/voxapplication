import 'dart:convert';
import 'dart:io';
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
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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
  //  SHARED: save content then open reader
  // ─────────────────────────────────────────────
  Future<void> _saveAndOpenReader({
    required String fileName,
    required String fileType,
    required String fileContent,
  }) async {
    if (_resolvedIsGuest) {
      setState(() => _statusMessage = 'Adding to temporary library...');
      final tempProvider = context.read<TempLibraryProvider>();
      tempProvider.add(
        TempLibraryItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          fileName: fileName,
          fileType: fileType,
          content: fileContent,
        ),
      );
    } else {
      setState(() => _statusMessage = 'Saving to library...');
      await FirebaseFirestore.instance.collection('library').add({
        'fileName': fileName,
        'fileType': fileType,
        'userId': _resolvedUid,
        'content': fileContent,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    if (!mounted) return;
    setState(() => _isUploading = false);

    SemanticsService.announce(
      'File ready. Reading started.',
      TextDirection.ltr,
    );

    final snackMsg = _resolvedIsGuest
        ? '"$fileName" added temporarily. Create an account to save it.'
        : fileContent.isNotEmpty
        ? '"$fileName" saved & reading started!'
        : '"$fileName" saved — text could not be extracted from this format.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(snackMsg),
        backgroundColor: const Color(0xFF333333),
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (fileContent.isNotEmpty) {
      final locale = context.read<LanguageProvider>().ttsLocale;
      final ttsService = context.read<TtsService>();
      final langProvider = context.read<LanguageProvider>();
      Navigator.of(context).pushReplacement(
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

  // ─────────────────────────────────────────────
  //  PICK & UPLOAD FILE
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File is too large. Maximum size is 200MB.'),
            backgroundColor: Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
          ),
        );
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
        fileContent = extension == 'pptx'
            ? _extractPptxTextFromZip(file.bytes!)
            : _extractPlainText(file.bytes!);
      } else if ((extension == 'docx' || extension == 'doc') &&
          file.bytes != null) {
        setState(() => _statusMessage = 'Extracting document text...');
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
      debugPrint(
        '📄 Extracted ${fileContent.length} chars from $fileName ($extension)',
      );

      await _saveAndOpenReader(
        fileName: fileName,
        fileType: extension,
        fileContent: fileContent,
      );
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upload failed. Please try again.'),
            backgroundColor: Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  //  SCAN DOCUMENT  (camera → ML Kit OCR → save & read)
  // ─────────────────────────────────────────────
  Future<void> _scanDocument() async {
    await _requestPermissionsIfNeeded();
    await _resolveUser();

    // Check then request camera permission
    PermissionStatus camStatus = await Permission.camera.status;
    if (!camStatus.isGranted) {
      camStatus = await Permission.camera.request();
    }

    if (camStatus.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Camera permission is blocked. Enable it in Settings.',
            ),
            backgroundColor: const Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'OPEN SETTINGS',
              textColor: const Color(0xFFF3E5AB),
              onPressed: openAppSettings,
            ),
          ),
        );
      }
      return;
    }

    if (!camStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is required to scan documents.'),
            backgroundColor: Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Ask: single or multi-page
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const Text(
              'Scan Document',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'How many pages do you want to scan?',
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
            const SizedBox(height: 20),
            _scanOptionTile(
              ctx,
              icon: Icons.photo_camera_rounded,
              title: 'Single Page',
              subtitle: 'Snap one photo and start reading',
              value: 'single',
            ),
            const SizedBox(height: 12),
            _scanOptionTile(
              ctx,
              icon: Icons.document_scanner_rounded,
              title: 'Multi-Page',
              subtitle: 'Take several photos — merged into one document',
              value: 'multi',
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    final picker = ImagePicker();
    final List<XFile> images = [];

    if (choice == 'single') {
      final img = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (img == null) return;
      images.add(img);
    } else {
      // Multi-page loop
      bool keepGoing = true;
      while (keepGoing && mounted) {
        final img = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 90,
        );
        if (img == null) break;
        images.add(img);
        if (!mounted) break;
        keepGoing =
            await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Text(
                  'Page ${images.length} captured',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                content: const Text('Scan another page?'),
                actions: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Add Page',
                      style: TextStyle(color: Color(0xFFF3E5AB)),
                    ),
                  ),
                ],
              ),
            ) ??
            false;
      }
    }

    if (images.isEmpty || !mounted) return;

    setState(() {
      _isUploading = true;
      _statusMessage = images.length == 1
          ? 'Recognising text...'
          : 'Reading page 1 of ${images.length}...';
    });

    try {
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final buffer = StringBuffer();

      for (int i = 0; i < images.length; i++) {
        if (images.length > 1) {
          setState(
            () =>
                _statusMessage = 'Reading page ${i + 1} of ${images.length}...',
          );
        }
        final inputImage = InputImage.fromFilePath(images[i].path);
        final result = await recognizer.processImage(inputImage);
        if (result.text.trim().isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n\n');
          buffer.write(result.text.trim());
        }
        try {
          File(images[i].path).deleteSync();
        } catch (_) {}
      }

      recognizer.close();

      String scanned = buffer.toString().trim();
      scanned = scanned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

      if (scanned.isEmpty) {
        setState(() => _isUploading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No text detected. Try better lighting or hold the camera steadier.',
              ),
              backgroundColor: Color(0xFF333333),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      debugPrint(
        '📷 Scanned ${scanned.length} chars, ${images.length} page(s)',
      );

      final now = DateTime.now();
      final fileName =
          'Scan ${now.day.toString().padLeft(2, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-${now.year} '
          '${now.hour.toString().padLeft(2, '0')}h'
          '${now.minute.toString().padLeft(2, '0')}';

      setState(() => _statusMessage = 'Saving scan...');
      await _saveAndOpenReader(
        fileName: fileName,
        fileType: 'scan',
        fileContent: scanned,
      );
    } catch (e) {
      debugPrint('Scan error: $e');
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scan failed. Please try again.'),
            backgroundColor: Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _scanOptionTile(
    BuildContext ctx, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pop(ctx, value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFD4B96A).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFFD4B96A), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
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
          extractor.extractText(startPageIndex: i, endPageIndex: i),
        );
      }
      document.dispose();
      return buffer.toString();
    } catch (e) {
      debugPrint('PDF extraction error: $e');
      return '';
    }
  }

  String _extractDocxTextFromZip(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final docFile = archive.findFile('word/document.xml');
      if (docFile == null) {
        debugPrint('DOCX: word/document.xml not found in archive');
        return '';
      }
      final xml = utf8.decode(
        docFile.content as List<int>,
        allowMalformed: true,
      );
      final regex = RegExp(r'<w:t[^>]*>(.*?)<\/w:t>', dotAll: true);
      final buffer = StringBuffer();
      for (final m in regex.allMatches(xml)) {
        final text = m.group(1) ?? '';
        if (text.isNotEmpty) buffer.write('$text ');
      }
      final paraRegex = RegExp(r'<w:p[ >]', dotAll: true);
      final withBreaks = xml.replaceAll(paraRegex, '\n<w:p ');
      final paraBuffer = StringBuffer();
      for (final m in regex.allMatches(withBreaks)) {
        paraBuffer.write(m.group(1) ?? '');
      }
      final result = paraBuffer.toString().trim();
      return result.isNotEmpty ? result : buffer.toString().trim();
    } catch (e) {
      debugPrint('DOCX ZIP extraction error: $e');
      return '';
    }
  }

  String _extractPptxTextFromZip(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final buffer = StringBuffer();
      final slideRegex = RegExp(r'^ppt/slides/slide\d+\.xml$');
      final slideFiles =
          archive.files.where((f) => slideRegex.hasMatch(f.name)).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      final textRegex = RegExp(r'<a:t[^>]*>(.*?)<\/a:t>', dotAll: true);
      for (final slideFile in slideFiles) {
        final xml = utf8.decode(
          slideFile.content as List<int>,
          allowMalformed: true,
        );
        String prev = '';
        for (final m in textRegex.allMatches(xml)) {
          final text = m.group(1)?.trim() ?? '';
          if (text.isNotEmpty && text != prev) {
            buffer.write('$text ');
            prev = text;
          }
        }
        buffer.write('\n');
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
      try {
        final archive = ZipDecoder().decodeBytes(bytes);
        final buffer = StringBuffer();
        final textRegex = RegExp(
          r'<(?:text:p|text:span|t|a:t|c)[^>]*>(.*?)<\/(?:text:p|text:span|t|a:t|c)>',
          dotAll: true,
        );
        for (final file in archive.files) {
          if (file.name.endsWith('.xml')) {
            final xml = utf8.decode(
              file.content as List<int>,
              allowMalformed: true,
            );
            for (final m in textRegex.allMatches(xml)) {
              final text =
                  m.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
              if (text.isNotEmpty) buffer.write('$text ');
            }
          }
        }
        final result = buffer.toString().trim();
        if (result.isNotEmpty) return result;
      } catch (_) {}
      final raw = utf8.decode(bytes, allowMalformed: true);
      final regex = RegExp(
        r'<(?:text:p|text:span|t|a:t|c)[^>]*>(.*?)<\/(?:text:p|text:span|t|a:t|c)>',
        dotAll: true,
      );
      final buffer = StringBuffer();
      for (final m in regex.allMatches(raw)) {
        final text =
            m.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
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
        title: const Text(
          'Upload Files',
          style: TextStyle(color: Colors.black),
        ),
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
                  Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 32,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.drive_folder_upload,
                      size: 72,
                      color: Colors.black38,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Upload a file or scan a\nphysical document with your camera',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 15,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Reading starts automatically',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),

                    // ── Guest notice ──────────────────────────
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
                              color: Colors.black.withOpacity(0.1),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.black54,
                                size: 18,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "You're browsing as a guest. Files will only be available until you close the app.",
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 36),

                    // ── CHOOSE FILE ───────────────────────────
                    Semantics(
                      label: 'Choose a file to upload and read aloud',
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _pickAnyFile,
                          icon: const Icon(Icons.upload_file_rounded, size: 20),
                          label: const Text(
                            'CHOOSE FILE',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: const Color(0xFFF3E5AB),
                            padding: const EdgeInsets.symmetric(vertical: 17),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            elevation: 3,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── OR divider ────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: Colors.black.withOpacity(0.15),
                            thickness: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.35),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: Colors.black.withOpacity(0.15),
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── SCAN DOCUMENT ─────────────────────────
                    Semantics(
                      label:
                          'Scan a physical document with your camera and read aloud',
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _scanDocument,
                          icon: const Icon(
                            Icons.document_scanner_rounded,
                            size: 20,
                          ),
                          label: const Text(
                            'SCAN DOCUMENT',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black,
                            side: const BorderSide(
                              color: Colors.black,
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 17),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Scanning tips ─────────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _tipRow(
                            Icons.wb_sunny_outlined,
                            'Good lighting improves accuracy',
                          ),
                          const SizedBox(height: 8),
                          _tipRow(
                            Icons.crop_free_rounded,
                            'Fill the frame with the text and hold camera steady',
                          ),
                          const SizedBox(height: 8),
                          _tipRow(
                            Icons.layers_rounded,
                            'Multi-page mode merges all pages into one document',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _tipRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: Colors.black38),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.black45,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
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
