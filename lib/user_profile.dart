import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  String? _base64Image;
  bool _isLoading = false;

  // Use UID as the document ID — matches Firestore rules
  String get _userId => FirebaseAuth.instance.currentUser?.uid ?? "anonymous";

  Future<void> _pickAndConvertImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 400,
      maxHeight: 400,
      imageQuality: 50,
    );

    if (image != null) {
      final imageBytes = await image.readAsBytes();
      setState(() {
        _base64Image = base64Encode(imageBytes);
      });
    }
  }

  Future<void> _saveToFirestore() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter an email address")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // FIX: Use UID as document ID (matches Firestore rule: match /users/{userId})
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId) // was: .doc(email) — now uses UID
          .set({
            'username': _nameController.text.trim(),
            'email': email,
            'phone': _phoneController.text.trim(),
            'photoBase64': _base64Image ?? "",
            'createdAt': FieldValue.serverTimestamp(),
            'userId': _userId, // store UID in doc for reference
          });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Profile Saved!")));

      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Backdrop decoration
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF3E5AB).withOpacity(0.4),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF3E5AB).withOpacity(0.2),
              ),
            ),
          ),

          // Main content
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 60,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "USER\nPROFILE",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Fill in your details to join the community.",
                        style: TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Photo upload
                      Center(
                        child: GestureDetector(
                          onTap: _pickAndConvertImage,
                          child: Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(
                                    color: const Color(0xFFF3E5AB),
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  radius: 55,
                                  backgroundColor: const Color(0xFFF9F9F9),
                                  backgroundImage: _base64Image != null
                                      ? MemoryImage(base64Decode(_base64Image!))
                                      : null,
                                  child: _base64Image == null
                                      ? const Icon(
                                          Icons.camera_alt_outlined,
                                          color: Colors.black26,
                                          size: 30,
                                        )
                                      : null,
                                ),
                              ),
                              Positioned(
                                bottom: 5,
                                right: 5,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Colors.black,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.edit,
                                    color: Color(0xFFF3E5AB),
                                    size: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),

                      _buildElegantField(
                        "Full Name",
                        _nameController,
                        Icons.person_outline,
                      ),
                      _buildElegantField(
                        "Email Address",
                        _emailController,
                        Icons.alternate_email,
                      ),
                      _buildElegantField(
                        "Phone Number",
                        _phoneController,
                        Icons.phone_android_outlined,
                      ),

                      const SizedBox(height: 50),

                      Center(
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.black,
                              )
                            : SizedBox(
                                width: 220,
                                height: 55,
                                child: ElevatedButton(
                                  onPressed: _saveToFirestore,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: const Color(0xFFF3E5AB),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    elevation: 8,
                                  ),
                                  child: const Text(
                                    "SAVE PROFILE",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildElegantField(
    String label,
    TextEditingController controller,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.black, size: 20),
          labelText: label,
          labelStyle: const TextStyle(color: Colors.black54, fontSize: 14),
          filled: true,
          fillColor: const Color(0xFFF3E5AB).withOpacity(0.1),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Colors.transparent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFFF3E5AB), width: 2),
          ),
        ),
      ),
    );
  }
}
