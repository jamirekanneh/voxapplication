import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  bool _isUploading = false;

  Future<void> _pickAnyFile() async {
    // UPDATED: ACCEPTS ALL COMMON DOCUMENT TYPES
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'txt'],
    );

    if (result != null) {
      setState(() => _isUploading = true);
      String fileName = result.files.first.name;
      String extension = result.files.first.extension ?? 'file';
      String userEmail =
          FirebaseAuth.instance.currentUser?.email ?? "demo@user.com";

      try {
        await FirebaseFirestore.instance.collection('library').add({
          'fileName': fileName,
          'fileType': extension,
          'userId': userEmail,
          'timestamp': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("File Uploaded Successfully!"),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 110, left: 20, right: 20),
            ),
          );
        }
      } catch (e) {
        print(e);
      } finally {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF2B3),
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
            ? const CircularProgressIndicator(color: Colors.black)
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
