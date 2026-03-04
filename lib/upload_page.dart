import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdf/syncfusion_flutter_pdf.dart';
import 'temp_library_provider.dart';

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

  Future<void> _pickAnyFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'txt'],
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

    // Validate file size — max 20MB
    if ((file.size) > 20 * 1024 * 1024) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("File is too large. Maximum size is 20MB."),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
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
      } else if ((extension == 'docx' || extension == 'doc') &&
          file.bytes != null) {
        setState(() => _statusMessage = "Extracting document text...");
        fileContent = _extractDocxText(file.bytes!);
      }

      fileContent = fileContent.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');

      if (_isAnonymous) {
        // ── Anonymous: store in memory only ──────────────
        setState(() => _statusMessage = "Adding to temporary library...");
        final tempProvider = context.read<TempLibraryProvider>();
        tempProvider.add(TempLibraryItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          fileName: fileName,
          fileType: extension,
          content: fileContent,
        ));
      } else {
        // ── Logged in: save to Firestore ─────────────────
        setState(() => _statusMessage = "Saving to library...");
        final userEmail =
            FirebaseAuth.instance.currentUser?.email ?? '';
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isAnonymous
                  ? '"$fileName" added temporarily. Create an account to save it.'
                  : fileContent.isNotEmpty
                      ? '"$fileName" uploaded & ready to read!'
                      : '"$fileName" uploaded (text extraction not available for this format)',
            ),
            backgroundColor:
                _isAnonymous ? Colors.orange[800] : Colors.grey[850],
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Upload error: $e");
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Upload failed. Please try again."),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
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
            extractor.extractText(startPageIndex: i, endPageIndex: i));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      appBar: AppBar(
        title: const Text("Upload Files",
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
                    const Text("Select any PDF, Word, or Text file",
                        style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 8),
                    Text(
                      "Text will be extracted and saved for reading",
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),

                    // Anonymous notice banner
                    if (_isAnonymous) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.orange[800]!.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.orange[800]!.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.orange[800], size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "You're browsing as a guest. Files will only be available until you close the app.",
                                style: TextStyle(
                                    color: Colors.orange[900],
                                    fontSize: 12,
                                    height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 30),
                    ElevatedButton(
                      onPressed: _pickAnyFile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      child: const Text("CHOOSE FILE",
                          style: TextStyle(color: Color(0xFFF3E5AB))),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}