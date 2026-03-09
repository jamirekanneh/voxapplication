import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:permission_handler/permission_handler.dart';
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
  String _statusMessage = "Uploading...";

  bool get _isAnonymous =>
      FirebaseAuth.instance.currentUser == null ||
      FirebaseAuth.instance.currentUser!.isAnonymous;

  Future<void> _requestPermissionsIfNeeded() async {
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      await Permission.microphone.request();
    }
  }

  Future<void> _pickAnyFile() async {
    await _requestPermissionsIfNeeded();

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null) return;

    setState(() {
      _isUploading = true;
      _statusMessage = "Reading file...";
    });

    final file = result.files.first;
    final String fileName = file.name;
    final String extension = (file.extension ?? 'file').toLowerCase();

    if (file.size > 200 * 1024 * 1024) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("File is too large. Maximum size is 200MB."),
            backgroundColor: Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    String fileContent = "";

    try {
      if (extension == 'txt' && file.bytes != null) {
        fileContent = String.fromCharCodes(file.bytes!);
      } else if (extension == 'pdf' && file.bytes != null) {
        setState(() => _statusMessage = "Extracting PDF text...");
        fileContent = await _extractPdfText(file.bytes!);
      } else if ((extension == 'ppt' || extension == 'pptx') &&
          file.bytes != null) {
        setState(() => _statusMessage = "Extracting presentation text...");
        fileContent = _extractPptxText(file.bytes!);
      } else if ((extension == 'docx' || extension == 'doc') &&
          file.bytes != null) {
        setState(() => _statusMessage = "Extracting document text...");
        fileContent = _extractDocxText(file.bytes!);
      } else if ((extension == 'txt' ||
              extension == 'md' ||
              extension == 'rtf' ||
              extension == 'csv' ||
              extension == 'epub') &&
          file.bytes != null) {
        setState(() => _statusMessage = "Reading text file...");
        fileContent = _extractPlainText(file.bytes!);
      } else if ((extension == 'xlsx' ||
              extension == 'xls' ||
              extension == 'odt' ||
              extension == 'odp') &&
          file.bytes != null) {
        setState(() => _statusMessage = "Extracting file text...");
        fileContent = _extractXmlBasedText(file.bytes!);
      } else if (file.bytes != null) {
        // Last resort: try reading as plain text
        setState(() => _statusMessage = "Reading file...");
        fileContent = _extractPlainText(file.bytes!);
      }

      fileContent = fileContent.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');

      if (_isAnonymous) {
        setState(() => _statusMessage = "Adding to temporary library...");
        final tempProvider = context.read<TempLibraryProvider>();
        tempProvider.add(
          TempLibraryItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            fileName: fileName,
            fileType: extension,
            content: fileContent,
          ),
        );
      } else {
        setState(() => _statusMessage = "Saving to library...");
        final userEmail = FirebaseAuth.instance.currentUser?.email ?? '';
        await FirebaseFirestore.instance.collection('library').add({
          'fileName': fileName,
          'fileType': extension,
          'userId': userEmail,
          'content': fileContent,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        setState(() => _isUploading = false);

        // Accessibility announcement
        SemanticsService.announce(
          'File uploaded. Reading started.',
          TextDirection.ltr,
        );

        final snackMsg = _isAnonymous
            ? '"$fileName" added temporarily. Create an account to save it.'
            : fileContent.isNotEmpty
            ? '"$fileName" uploaded & reading started!'
            : '"$fileName" uploaded (text extraction not available for this format)';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackMsg),
            backgroundColor: const Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Auto-start reading if we have content
        if (fileContent.isNotEmpty) {
          final locale = context.read<LanguageProvider>().ttsLocale;
          final ttsService = context.read<TtsService>();
          final langProvider = context.read<LanguageProvider>();
          final nav = Navigator.of(context);

          // Replace upload page with reader directly — avoids context.mounted issues
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
      debugPrint("Upload error: $e");
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Upload failed. Please try again."),
            backgroundColor: Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

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
      debugPrint("PDF extraction error: $e");
      return "";
    }
  }

  String _extractDocxText(List<int> bytes) {
    try {
      final raw = String.fromCharCodes(bytes);
      final regex = RegExp(r'<w:t[^>]*>(.*?)<\/w:t>', dotAll: true);
      final matches = regex.allMatches(raw);
      final buffer = StringBuffer();
      for (final m in matches) buffer.write('${m.group(1)} ');
      return buffer.toString().trim();
    } catch (e) {
      debugPrint("DOCX extraction error: $e");
      return "";
    }
  }

  String _extractPptxText(List<int> bytes) {
    try {
      // PPTX is a ZIP archive — slide text lives in ppt/slides/slide*.xml
      // inside <a:t> tags. We parse the raw bytes as a string and extract them.
      final raw = String.fromCharCodes(bytes);
      final regex = RegExp(r'<a:t[^>]*>(.*?)<\/a:t>', dotAll: true);
      final matches = regex.allMatches(raw);
      final buffer = StringBuffer();
      String prev = '';
      for (final m in matches) {
        final text = m.group(1)?.trim() ?? '';
        if (text.isNotEmpty && text != prev) {
          buffer.write('$text ');
          prev = text;
        }
      }
      return buffer.toString().trim();
    } catch (e) {
      debugPrint("PPTX extraction error: $e");
      return "";
    }
  }

  /// Plain text, markdown, RTF, CSV, EPUB (strip XML/HTML tags)
  String _extractPlainText(List<int> bytes) {
    try {
      String raw = String.fromCharCodes(bytes);
      // Strip XML/HTML tags if present
      raw = raw.replaceAll(RegExp(r'<[^>]+>'), ' ');
      // Collapse whitespace
      raw = raw.replaceAll(RegExp(r'[ \t]+'), ' ');
      raw = raw.replaceAll(RegExp(r'\n{3,}'), '\n\n');
      return raw.trim();
    } catch (e) {
      debugPrint("Plain text extraction error: \$e");
      return "";
    }
  }

  /// ODT, ODP, XLSX/XLS — Office Open XML / ODF (ZIP-based, XML inside)
  String _extractXmlBasedText(List<int> bytes) {
    try {
      final raw = String.fromCharCodes(bytes);
      // Grab all text-ish XML tags used by ODF and OOXML
      final regex = RegExp(
        r'<(?:text:p|text:span|t|a:t|c)[^>]*>(.*?)<\/(?:text:p|text:span|t|a:t|c)>',
        dotAll: true,
      );
      final matches = regex.allMatches(raw);
      final buffer = StringBuffer();
      for (final m in matches) {
        final text =
            m.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '')?.trim() ?? '';
        if (text.isNotEmpty) buffer.write('\$text ');
      }
      return buffer.toString().trim();
    } catch (e) {
      debugPrint("XML-based extraction error: \$e");
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      appBar: AppBar(
        title: const Text(
          "Upload Files",
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
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.drive_folder_upload,
                      size: 80,
                      color: Colors.black54,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Select any file — PDF, Word, PPT, TXT, Excel and more",
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Reading will start automatically after upload",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),

                    if (_isAnonymous) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.black.withOpacity(0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.black54,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
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
                      ),
                    ],

                    const SizedBox(height: 30),
                    Semantics(
                      label: 'Choose a file to upload and read aloud',
                      child: ElevatedButton(
                        onPressed: _pickAnyFile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          minimumSize: const Size(200, 56),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          "CHOOSE FILE",
                          style: TextStyle(
                            color: Color(0xFFF3E5AB),
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
