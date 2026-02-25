import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  bool _isUploading = false;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _tts.setLanguage("en-US");
    _tts.setPitch(1.0);
    _tts.setSpeechRate(0.5);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _pickAnyFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'txt'],
      withData: true, // Needed to read file bytes / text
    );

    if (result != null) {
      setState(() => _isUploading = true);
      String fileName = result.files.first.name;
      String extension = result.files.first.extension ?? 'file';
      String userEmail =
          FirebaseAuth.instance.currentUser?.email ?? "demo@user.com";

      // Try to extract text content (works best with .txt files)
      String fileContent = "";
      if (extension == 'txt' && result.files.first.bytes != null) {
        fileContent = String.fromCharCodes(result.files.first.bytes!);
      }

      try {
        await FirebaseFirestore.instance.collection('library').add({
          'fileName': fileName,
          'fileType': extension,
          'userId': userEmail,
          'timestamp': FieldValue.serverTimestamp(),
        });

        setState(() => _isUploading = false);

        if (mounted) {
          // Show file viewer bottom sheet then auto-start reading
          await _showFileAndRead(fileName, fileContent);
        }
      } catch (e) {
        debugPrint(e.toString());
        setState(() => _isUploading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Upload failed. Please try again.")),
          );
        }
      }
    }
  }

  Future<void> _showFileAndRead(String fileName, String content) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF3E5AB),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, sc) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  controller: sc,
                  child: Text(
                    content.isNotEmpty
                        ? content
                        : "File uploaded successfully!\n\nNote: Full text extraction is available for .txt files. For PDF/Word/PPT files, reading will announce the file name.",
                    style: const TextStyle(fontSize: 15, height: 1.7),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("Start Reading Now"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final textToRead = content.isNotEmpty
                        ? content
                        : "Reading $fileName now.";
                    await _tts.speak(textToRead);
                    if (mounted) Navigator.pop(context); // back to home
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context); // back to home without reading
                  },
                  child: const Text(
                    "Go to Library",
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.black),
                  SizedBox(height: 16),
                  Text("Uploading...", style: TextStyle(color: Colors.black54)),
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
                    "Select any PDF, Word, or PowerPoint file",
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "File will open and start reading automatically",
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
