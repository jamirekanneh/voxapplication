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
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'theme_provider.dart';
import 'temp_library_provider.dart';
import 'language_provider.dart';
import 'tts_service.dart';
import 'reader_page.dart';
import 'analytics_service.dart';
import 'services/auth_session.dart';
import 'services/mic_coordinator.dart';
import 'services/document_text_extractor.dart';

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

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  RESOLVE USER
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  SHARED: save content then open reader
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _saveAndOpenReader({
    required String fileName,
    required String fileType,
    required String fileContent,
  }) async {
    await MicCoordinator.instance.yieldFromAssistant();
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
      try {
        const firestoreMaxChars = 900000;
        final storedContent = fileContent.length > firestoreMaxChars
            ? '${fileContent.substring(0, firestoreMaxChars)}\n\n[Document truncated for cloud storage — full text is available while reading now.]'
            : fileContent;
        await FirebaseFirestore.instance.collection('library').add({
          'fileName': fileName,
          'fileType': fileType,
          'userId': _resolvedUid,
          'content': storedContent,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Firestore library save failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not save "$fileName" to cloud (${e.toString().split('\n').first}). Reading locally.',
              ),
              backgroundColor: VoxColors.surface(context),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }

    // Track file upload operation
    AnalyticsService.instance.recordFileOperation('upload');

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
        : '"$fileName" saved â€” text could not be extracted from this format.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(snackMsg),
        backgroundColor: VoxColors.surface(context),
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

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  FILE VALIDATION
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _isValidFile(PlatformFile file, String extension) {
    // Define allowed file types and their size limits
    const allowedTypes = {
      // Text documents
      'txt': 10 * 1024 * 1024,    // 10MB
      'md': 10 * 1024 * 1024,     // 10MB
      'rtf': 10 * 1024 * 1024,    // 10MB
      'csv': 10 * 1024 * 1024,    // 10MB

      // Documents
      'pdf': 50 * 1024 * 1024,    // 50MB
      'doc': 25 * 1024 * 1024,    // 25MB
      'docx': 25 * 1024 * 1024,   // 25MB

      // Presentations
      'ppt': 50 * 1024 * 1024,    // 50MB
      'pptx': 50 * 1024 * 1024,   // 50MB
      'pptm': 50 * 1024 * 1024,   // 50MB
      'potx': 50 * 1024 * 1024,   // 50MB
      'ppsx': 50 * 1024 * 1024,   // 50MB
      'pps': 50 * 1024 * 1024,    // 50MB
      'pot': 50 * 1024 * 1024,    // 50MB

      // Spreadsheets
      'xls': 25 * 1024 * 1024,    // 25MB
      'xlsx': 25 * 1024 * 1024,   // 25MB

      // Images (OCR)
      'jpg': 25 * 1024 * 1024,
      'jpeg': 25 * 1024 * 1024,
      'png': 25 * 1024 * 1024,
      'webp': 25 * 1024 * 1024,
      'heic': 25 * 1024 * 1024,
      'bmp': 25 * 1024 * 1024,

      // Other
      'epub': 25 * 1024 * 1024,   // 25MB
      'odt': 25 * 1024 * 1024,    // 25MB
      'odp': 25 * 1024 * 1024,    // 25MB
    };

    // Check if file type is allowed
    if (!allowedTypes.containsKey(extension)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File type .$extension is not supported. Supported types: ${allowedTypes.keys.join(', ')}'),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    // Check file size against type-specific limit
    final maxSize = allowedTypes[extension]!;
    if (file.size > maxSize) {
      final maxSizeMB = (maxSize / (1024 * 1024)).round();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File is too large. Maximum size for .$extension files is ${maxSizeMB}MB.'),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    // Check for empty files
    if (file.size == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Cannot upload empty files.'),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    return true;
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  PICK & UPLOAD FILE
  // ────────────────────────────────────────────────────────────
  Future<void> _pickAnyFile() async {
    await _requestPermissionsIfNeeded();
    await _resolveUser();
    await MicCoordinator.instance.yieldFromAssistant();

    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    if (result.files.length > 1 &&
        result.files.every((f) => _isImageExtension(_fileExtension(f)))) {
      await _readUploadedImages(result.files);
      return;
    }

    if (result.files.length > 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Select one document at a time, or select multiple photos only.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() {
      _isUploading = true;
      _statusMessage = 'Reading file...';
    });

    final file = result.files.first;
    final String fileName = file.name;
    final String extension = _fileExtension(file);

    Uint8List? fileBytes = file.bytes;
    if (fileBytes == null && file.path != null) {
      try {
        fileBytes = await File(file.path!).readAsBytes();
      } catch (e) {
        debugPrint('File read error: $e');
      }
    }

    if (fileBytes == null || fileBytes.isEmpty) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Could not read this file. Try again or use a smaller file.',
            ),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Enhanced file validation
    if (!_isValidFile(file, extension)) {
      setState(() => _isUploading = false);
      return;
    }

    if (file.size > 50 * 1024 * 1024) { // Reduced to 50MB for better security
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('File is too large. Maximum size is 50MB.'),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    String fileContent = '';

    try {
      if (extension == 'txt' && fileBytes != null) {
        fileContent = utf8.decode(fileBytes, allowMalformed: true);
      } else if (extension == 'pdf') {
        setState(() => _statusMessage = 'Extracting PDF text...');
        fileContent = await _extractPdfText(fileBytes);
      } else if (_isImageExtension(extension)) {
        setState(() => _statusMessage = 'Reading text from image...');
        fileContent = await _extractTextFromImage(
          bytes: fileBytes,
          filePath: file.path,
          fileName: fileName,
        );
      } else if (_isPresentationExtension(extension)) {
        setState(() => _statusMessage = 'Extracting slide text (ignoring images)...');
        fileContent = _extractPresentationText(fileBytes, extension);
        if (fileContent.isEmpty) {
          fileContent = _extractXmlBasedText(fileBytes);
        }
      } else if ((extension == 'docx' || extension == 'doc') &&
          fileBytes != null) {
        setState(() => _statusMessage = 'Extracting text (ignoring images)...');
        fileContent = DocumentTextExtractor.extractDoc(
          fileBytes,
          extension: extension,
        );
      } else if ((extension == 'md' ||
              extension == 'rtf' ||
              extension == 'csv' ||
              extension == 'epub') &&
          fileBytes != null) {
        setState(() => _statusMessage = 'Reading text file...');
        fileContent = _extractPlainText(fileBytes);
      } else if ((extension == 'xlsx' ||
              extension == 'xls' ||
              extension == 'odt' ||
              extension == 'odp') &&
          fileBytes != null) {
        setState(() => _statusMessage = 'Extracting file text...');
        fileContent = _extractXmlBasedText(fileBytes);
      } else if (fileBytes != null) {
        setState(() => _statusMessage = 'Reading file...');
        fileContent = _extractPlainText(fileBytes);
      }

      fileContent = fileContent.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');
      debugPrint(
        'Extracted ${fileContent.length} chars from $fileName ($extension)',
      );

      if (fileContent.isEmpty) {
        setState(() => _isUploading = false);
        await _alertImageOnlyUpload(
          fileName: fileName,
          extension: extension,
        );
        return;
      }

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
          SnackBar(
            content: const Text('Upload failed. Please try again.'),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  SCAN DOCUMENT  (camera â†’ ML Kit OCR â†’ save & read)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _scanDocument() async {
    await _requestPermissionsIfNeeded();
    await _resolveUser();
    await MicCoordinator.instance.yieldFromAssistant();

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
            backgroundColor: VoxColors.surface(context),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'OPEN SETTINGS',
              textColor: VoxColors.primary(context),
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

    if (!mounted) return;

    // Ask: single or multi-page
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: VoxColors.surface(context),
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
                color: VoxColors.border(context),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Text(
              'Scan Document',
              style: TextStyle(
                color: VoxColors.onSurface(context),
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'How many pages do you want to scan?',
              style: TextStyle(color: VoxColors.textSecondary(context), fontSize: 13),
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
              subtitle: 'Take several photos â€” merged into one document',
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
                backgroundColor: VoxColors.surface(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: VoxColors.border(context)),
                ),
                title: Text(
                  'Page ${images.length} captured',
                  style: TextStyle(fontWeight: FontWeight.bold, color: VoxColors.onSurface(context)),
                ),
                content: Text('Scan another page?', style: TextStyle(color: VoxColors.textSecondary(context))),
                actions: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      'Done',
                      style: TextStyle(color: VoxColors.textSecondary(context)),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VoxColors.primary(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Add Page',
                      style: TextStyle(color: VoxColors.onPrimary(context)),
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
        await _alertImageOnlyUpload(
          fileName: 'scan',
          extension: 'scan',
        );
        return;
      }

      debugPrint(
        'ðŸ“· Scanned ${scanned.length} chars, ${images.length} page(s)',
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
          SnackBar(
            content: const Text('Scan failed. Please try again.'),
            backgroundColor: VoxColors.danger,
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
          color: VoxColors.cardFill(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: VoxColors.border(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: VoxColors.primary(context).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: VoxColors.primary(context), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: VoxColors.onSurface(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(color: VoxColors.textSecondary(context), fontSize: 12),
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

  String _fileExtension(PlatformFile file) {
    final fromPicker = file.extension?.toLowerCase();
    if (fromPicker != null && fromPicker.isNotEmpty) return fromPicker;
    final name = file.name;
    if (name.contains('.')) return name.split('.').last.toLowerCase();
    return 'file';
  }

  bool _isImageExtension(String extension) =>
      const {'jpg', 'jpeg', 'png', 'webp', 'heic', 'bmp'}.contains(extension);

  /// Text + spoken alert when an upload has no readable text (image-only).
  Future<void> _alertImageOnlyUpload({
    required String fileName,
    required String extension,
  }) async {
    if (!mounted) return;

    final isPhoto =
        _isImageExtension(extension) || extension == 'scan' || extension == 'jpg';
    final screenMessage = isPhoto
        ? 'This upload only contains images — no text was found to read. '
            'Try Scan Document with good lighting, or a clearer photo.'
        : 'This upload only contains images — no readable text in "$fileName". '
            'Embedded pictures are ignored. Add typed text in Word or PowerPoint, '
            'or use Scan Document for photo pages.';
    const voiceMessage =
        'This upload only contains images. No text to read aloud.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(screenMessage),
        backgroundColor: VoxColors.danger,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 7),
      ),
    );
    SemanticsService.announce(voiceMessage, TextDirection.ltr);

    try {
      final locale = context.read<LanguageProvider>().ttsLocale;
      await context.read<TtsService>().speakBrief(voiceMessage, locale);
    } catch (e) {
      debugPrint('Image-only upload alert TTS failed: $e');
    }
  }

  Future<String> _extractTextFromImage({
    required Uint8List bytes,
    String? filePath,
    required String fileName,
  }) async {
    File? tempFile;
    try {
      String path = filePath ?? '';
      if (path.isEmpty) {
        final dir = await getTemporaryDirectory();
        final ext = _fileExtension(
          PlatformFile(name: fileName, size: bytes.length, bytes: bytes),
        );
        tempFile = File(
          '${dir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.$ext',
        );
        await tempFile.writeAsBytes(bytes);
        path = tempFile.path;
      }

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(InputImage.fromFilePath(path));
      recognizer.close();
      return result.text.trim();
    } catch (e) {
      debugPrint('Image OCR error: $e');
      return '';
    } finally {
      try {
        tempFile?.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _readUploadedImages(List<PlatformFile> files) async {
    setState(() {
      _isUploading = true;
      _statusMessage = files.length == 1
          ? 'Reading text from image...'
          : 'Reading image 1 of ${files.length}...';
    });

    try {
      final buffer = StringBuffer();
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        if (files.length > 1 && mounted) {
          setState(
            () => _statusMessage = 'Reading image ${i + 1} of ${files.length}...',
          );
        }

        Uint8List? bytes = file.bytes;
        if ((bytes == null || bytes.isEmpty) && file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }
        if (bytes == null || bytes.isEmpty) continue;

        final ext = _fileExtension(file);
        if (!_isValidFile(file, ext)) continue;

        final text = await _extractTextFromImage(
          bytes: bytes,
          filePath: file.path,
          fileName: file.name,
        );
        if (text.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n\n');
          buffer.write(text);
        }
      }

      final combined = buffer.toString().trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');
      if (combined.isEmpty) {
        setState(() => _isUploading = false);
        await _alertImageOnlyUpload(
          fileName: files.length == 1 ? files.first.name : 'photos',
          extension: _fileExtension(files.first),
        );
        return;
      }

      final label = files.length == 1
          ? files.first.name
          : 'Photos (${files.length})';
      await _saveAndOpenReader(
        fileName: label,
        fileType: _fileExtension(files.first),
        fileContent: combined,
      );
    } catch (e) {
      debugPrint('Image upload read error: $e');
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not read image(s). Please try again.'),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ────────────────────────────────────────────────────────────
  //  TEXT EXTRACTORS
  // ────────────────────────────────────────────────────────────

  Future<String> _extractPdfText(List<int> bytes) async {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);
      final buffer = StringBuffer();
      for (int i = 0; i < document.pages.count; i++) {
        final pageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        if (pageText.trim().isNotEmpty) {
          buffer.writeln(pageText);
        }
      }
      var result = buffer.toString().trim();
      if (result.isEmpty) {
        result = extractor.extractText().trim();
      }
      return result;
    } catch (e) {
      debugPrint('PDF extraction error: $e');
      return '';
    } finally {
      document?.dispose();
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

  bool _isPresentationExtension(String extension) =>
      const {'ppt', 'pptx', 'pptm', 'potx', 'ppsx', 'pps', 'pot', 'odp'}
          .contains(extension);

  bool _isZipBytes(List<int> bytes) =>
      bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;

  String _normalizeArchivePath(String path) =>
      path.replaceAll('\\', '/').toLowerCase();

  int _slideNumberFromPath(String path) {
    final match = RegExp(r'slide(\d+)').firstMatch(path);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
  }

  String _decodeXmlText(String raw) {
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

  void _appendUniqueText(StringBuffer buffer, Set<String> seen, String text) {
    final cleaned = _decodeXmlText(text);
    if (cleaned.length < 2) return;
    if (seen.add(cleaned)) {
      buffer.writeln(cleaned);
    }
  }

  List<int>? _archiveEntryBytes(ArchiveFile file) {
    try {
      final raw = file.content;
      if (raw != null && raw.isNotEmpty) return raw as List<int>;
    } catch (_) {}
    return null;
  }

  int _presentationXmlPriority(String path) {
    if (RegExp(r'ppt/slides/slide\d+\.xml').hasMatch(path)) {
      return _slideNumberFromPath(path);
    }
    if (path.contains('ppt/notesslides/')) return 1000 + _slideNumberFromPath(path);
    if (path.contains('ppt/slidelayouts/')) return 2000;
    if (path.contains('ppt/slidemasters/')) return 3000;
    if (path.contains('ppt/')) return 4000;
    return 5000;
  }

  void _extractTextFromPresentationXml(
    String xml,
    StringBuffer buffer,
    Set<String> seen,
  ) {
    final patterns = [
      RegExp(r'<a:t[^>]*>(.*?)</a:t>', dotAll: true),
      RegExp(r'<a14:t[^>]*>(.*?)</a14:t>', dotAll: true),
      RegExp(r'<p:t[^>]*>(.*?)</p:t>', dotAll: true),
      RegExp(r'<dsp:t[^>]*>(.*?)</dsp:t>', dotAll: true),
      RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true),
      RegExp(r'<text:p[^>]*>(.*?)</text:p>', dotAll: true),
      RegExp(r'<text:span[^>]*>(.*?)</text:span>', dotAll: true),
      // DrawingML / legacy runs without namespace prefix in inner XML
      RegExp(r'<(?:(?:a|p|a14|p14):)?t[^>]*>(.*?)</(?:(?:a|p|a14|p14):)?t>', dotAll: true),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(xml)) {
        _appendUniqueText(buffer, seen, match.group(1) ?? '');
      }
    }
  }

  String _extractPptxTextFromZip(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final buffer = StringBuffer();
      final seen = <String>{};

      final xmlFiles = archive.files
          .where((f) {
            if (!f.isFile) return false;
            final path = _normalizeArchivePath(f.name);
            return path.endsWith('.xml') &&
                (path.contains('ppt/') || path == 'content.xml');
          })
          .toList()
        ..sort(
          (a, b) => _presentationXmlPriority(_normalizeArchivePath(a.name))
              .compareTo(_presentationXmlPriority(_normalizeArchivePath(b.name))),
        );

      for (final file in xmlFiles) {
        final entryBytes = _archiveEntryBytes(file);
        if (entryBytes == null || entryBytes.isEmpty) continue;
        final xml = utf8.decode(entryBytes, allowMalformed: true);
        _extractTextFromPresentationXml(xml, buffer, seen);
      }

      debugPrint(
        'PPTX: scanned ${xmlFiles.length} XML parts, ${seen.length} text runs',
      );
      return buffer.toString().trim();
    } catch (e) {
      debugPrint('PPTX ZIP extraction error: $e');
      return '';
    }
  }

  String _extractOdpText(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final buffer = StringBuffer();
      final seen = <String>{};

      ArchiveFile? contentFile;
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final path = _normalizeArchivePath(f.name);
        if (path == 'content.xml' || path.endsWith('/content.xml')) {
          contentFile = f;
          break;
        }
      }
      if (contentFile == null) return '';

      final entryBytes = _archiveEntryBytes(contentFile);
      if (entryBytes == null) return '';

      final xml = utf8.decode(entryBytes, allowMalformed: true);
      _extractTextFromPresentationXml(xml, buffer, seen);
      return buffer.toString().trim();
    } catch (e) {
      debugPrint('ODP extraction error: $e');
      return '';
    }
  }

  bool _isMeaningfulSlideText(String text) {
    if (text.length < 3) return false;
    final letterCount = RegExp(r'[A-Za-z]').allMatches(text).length;
    return letterCount >= 2;
  }

  String _extractLegacyPptBinaryText(List<int> bytes) {
    final found = <String>{};
    final buffer = StringBuffer();

    void addIfMeaningful(String value) {
      final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (_isMeaningfulSlideText(cleaned) && found.add(cleaned)) {
        buffer.writeln(cleaned);
      }
    }

    // UTF-16 LE runs (common in legacy Office binary files)
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

    // ASCII runs as a backup
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

    return buffer.toString().trim();
  }

  String _extractPresentationText(List<int> bytes, String extension) {
    if (extension == 'odp') {
      return DocumentTextExtractor.extractOdp(bytes);
    }

    final isOpenXml =
        const {'pptx', 'pptm', 'potx', 'ppsx', 'pps'}.contains(extension) ||
            DocumentTextExtractor.isZipBytes(bytes);

    if (isOpenXml) {
      return DocumentTextExtractor.extractPptx(bytes);
    }

    // .ppt / .pot may be OOXML zip or legacy binary
    final fromZip = DocumentTextExtractor.extractPptx(bytes);
    if (fromZip.isNotEmpty) return fromZip;

    return _extractLegacyPptBinaryText(bytes);
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

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  BUILD
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        title: Text(
          lang.t('upload_files_title'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _isUploading
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF4B9EFF)),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
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
                      color: Colors.white12,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      lang.t('upload_hero'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      lang.t('upload_reading_starts'),
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      lang.t('upload_supported_types_label'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    // â”€â”€ Guest notice â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    FutureBuilder<bool>(
                      future: _isGuestAsync(),
                      builder: (context, snap) {
                        if (snap.data != true) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.only(top: 20),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Color(0xFF4B9EFF),
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  lang.t('upload_guest_notice'),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
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

                    // â”€â”€ CHOOSE FILE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Semantics(
                      label: 'Choose a file to upload and read aloud',
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _pickAnyFile,
                          icon: const Icon(Icons.upload_file_rounded, size: 20),
                          label: Text(
                            lang.t('upload_choose_file'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4B9EFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            elevation: 8,
                            shadowColor: const Color(0xFF4B9EFF).withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // â”€â”€ OR divider â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: Colors.white.withValues(alpha: 0.1),
                            thickness: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            lang.t('upload_or'),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: Colors.white.withValues(alpha: 0.1),
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // â”€â”€ SCAN DOCUMENT â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                          label: Text(
                            lang.t('upload_scan_document'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // â”€â”€ Scanning tips â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _tipRow(
                            Icons.wb_sunny_outlined,
                            lang.t('upload_tip_lighting'),
                          ),
                          const SizedBox(height: 8),
                          _tipRow(
                            Icons.crop_free_rounded,
                            lang.t('upload_tip_frame'),
                          ),
                          const SizedBox(height: 8),
                          _tipRow(
                            Icons.layers_rounded,
                            lang.t('upload_tip_multipage'),
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
        Icon(icon, size: 15, color: const Color(0xFF4B9EFF).withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Future<bool> _isGuestAsync() async {
    return AuthSession.usesGuestExperience();
  }
}

