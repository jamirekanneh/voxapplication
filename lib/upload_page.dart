import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  bool _isUploading = false;
  String _statusMessage = "Uploading...";

  @override
  Future<void> _pickAnyFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'txt'],
      withData: true,
    );

    if (result != null) {
      setState(() {
        _isUploading = true;
        _statusMessage = "Reading file...";
      });

      final file = result.files.first;
      final String fileName = file.name;
      final String extension = (file.extension ?? 'file').toLowerCase();
      final String userEmail =
          FirebaseAuth.instance.currentUser?.email ?? "demo@user.com";

      String fileContent = "";

      try {
        // ── Extract text based on file type ──
        if (extension == 'txt' && file.bytes != null) {
          fileContent = String.fromCharCodes(file.bytes!);
        } else if (extension == 'pdf' && file.bytes != null) {
          setState(() => _statusMessage = "Extracting PDF text...");
          fileContent = await _extractPdfText(file.bytes!);
        } else if ((extension == 'docx' || extension == 'doc') &&
            file.bytes != null) {
          setState(() => _statusMessage = "Extracting document text...");
          fileContent = _extractDocxText(file.bytes!);
        } else {
          fileContent = "";
        }

        // Clean up extracted text
        fileContent = fileContent.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');

        setState(() => _statusMessage = "Saving to library...");

        await FirebaseFirestore.instance.collection('library').add({
          'fileName': fileName,
          'fileType': extension,
          'userId': userEmail,
          'content': fileContent,
          'timestamp': FieldValue.serverTimestamp(),
        });

        setState(() => _isUploading = false);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                fileContent.isNotEmpty
                    ? '"$fileName" uploaded & ready to read!'
                    : '"$fileName" uploaded (text extraction not available for this format)',
              ),
              backgroundColor: Colors.grey[850],
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context); // back to home
        }
      } catch (e) {
        debugPrint("Upload error: $e");
        setState(() => _isUploading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Upload failed. Please try again."),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Extract text from PDF bytes using Syncfusion
  Future<String> _extractPdfText(List<int> bytes) async {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final StringBuffer buffer = StringBuffer();
      for (int i = 0; i < document.pages.count; i++) {
        final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
        buffer.writeln(text);
      }
      document.dispose();
      return buffer.toString();
    } catch (e) {
      debugPrint("PDF extraction error: $e");
      return "";
    }
  }

  /// Basic DOCX text extraction — reads raw XML and strips tags
  String _extractDocxText(List<int> bytes) {
    try {
      // DOCX is a ZIP — decode as string and extract text between <w:t> tags
      final raw = String.fromCharCodes(bytes);
      final regex = RegExp(r'<w:t[^>]*>(.*?)<\/w:t>', dotAll: true);
      final matches = regex.allMatches(raw);
      final buffer = StringBuffer();
      for (final m in matches) {
        buffer.write('${m.group(1)} ');
      }
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
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.drive_folder_upload,
                    size: 80,
                    color: Colors.black54,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Select any PDF, Word, or Text file",
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Text will be extracted and saved for reading",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: _pickAnyFile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
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
                      style: TextStyle(color: Color(0xFFF3E5AB)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
