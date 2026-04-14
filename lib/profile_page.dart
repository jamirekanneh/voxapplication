import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
//  ProfilePage
//  • Has account  → shows name, email, photo + edit
//  • Anonymous    → account creation form
// ─────────────────────────────────────────────
class ProfilePage extends StatefulWidget {
  final bool isAnonymous;
  final String username;
  final String email;
  final String? base64Image;
  final String? photoUrl;
  final VoidCallback onProfileUpdated;

  const ProfilePage({
    super.key,
    required this.isAnonymous,
    required this.username,
    required this.email,
    required this.base64Image,
    required this.photoUrl,
    required this.onProfileUpdated,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  bool _isEditing = false;
  bool _isSaving = false;

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  String? _base64Image;

  // Anonymous flow stages
  String _anonStage = 'join'; // 'join' | 'returning' | 'awaiting_link'
  bool _anonLoading = false;

  // Spinning ring for awaiting_link
  late AnimationController _rotateController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.username);
    _emailController = TextEditingController(text: widget.email);
    _base64Image = widget.base64Image;
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  // ── Pick image ────────────────────────────────
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 400,
      maxHeight: 400,
      imageQuality: 50,
    );
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() => _base64Image = base64Encode(bytes));
    }
  }

  // ── Save edits (existing user) ────────────────
  Future<void> _saveEdits() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack("Name can't be empty");
      return;
    }
    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({
        'username': name,
        'photoBase64': _base64Image ?? '',
      });
      widget.onProfileUpdated();
      if (mounted) setState(() => _isEditing = false);
      _showSnack("Profile updated");
    } catch (e) {
      _showSnack("Error saving: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Anonymous: check email ────────────────────
  Future<void> _onAnonSaveTapped() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty || email.isEmpty) {
      _showSnack("Please fill in your name and email");
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      _showSnack("Please enter a valid email address");
      return;
    }

    setState(() => _anonLoading = true);

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (!mounted) return;
    setState(() => _anonLoading = false);

    if (snapshot.docs.isNotEmpty) {
      setState(() => _anonStage = 'returning');
    } else {
      await _saveNewAnonProfile();
    }
  }

  // ── Anonymous: save brand new profile ─────────
  Future<void> _saveNewAnonProfile() async {
    setState(() => _anonLoading = true);
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        final cred = await FirebaseAuth.instance.signInAnonymously();
        user = cred.user;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .set({
        'username': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'photoBase64': _base64Image ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'userId': user.uid,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasProfile', true);
      await prefs.setString('userEmail', _emailController.text.trim());

      widget.onProfileUpdated();
      if (mounted) {
        _showSnack("Account created! Your data is now being saved.");
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnack("Error: $e");
    } finally {
      if (mounted) setState(() => _anonLoading = false);
    }
  }

  // ── Anonymous: send magic link ────────────────
  Future<void> _sendMagicLink() async {
    setState(() => _anonLoading = true);
    try {
      final email = _emailController.text.trim();
      final acs = ActionCodeSettings(
        url:
            'https://vox-application-76ecd.firebaseapp.com/verify?email=$email',
        handleCodeInApp: true,
        androidPackageName: 'com.example.voxapplication',
        androidInstallApp: true,
        androidMinimumVersion: '21',
      );
      await FirebaseAuth.instance.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: acs,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pendingEmailLink', email);
      if (!mounted) return;
      setState(() => _anonStage = 'awaiting_link');
    } catch (e) {
      _showSnack("Error sending link: $e");
    } finally {
      if (mounted) setState(() => _anonLoading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─────────────────────────────────────────────
  //  AVATAR WIDGET
  // ─────────────────────────────────────────────
  Widget _buildAvatar({double radius = 52}) {
    if (_base64Image != null && _base64Image!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: MemoryImage(base64Decode(_base64Image!)),
      );
    }
    if (widget.photoUrl != null && widget.photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(widget.photoUrl!),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFBFA050),
      child: Text(
        widget.username.isNotEmpty
            ? widget.username[0].toUpperCase()
            : '?',
        style: TextStyle(
          fontSize: radius * 0.85,
          fontWeight: FontWeight.w900,
          color: const Color(0xFFF0F4FF),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: widget.isAnonymous
          ? _buildAnonView()
          : _buildProfileView(),
    );
  }

  // ─────────────────────────────────────────────
  //  EXISTING USER PROFILE VIEW
  // ─────────────────────────────────────────────
  Widget _buildProfileView() {
    return Stack(
      children: [
        // Background blob top right
        Positioned(
          top: -60,
          right: -60,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF0F4FF).withValues(alpha: 0.5),
            ),
          ),
        ),
        // Background blob bottom left
        Positioned(
          bottom: -80,
          left: -60,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF0F4FF).withValues(alpha: 0.25),
            ),
          ),
        ),

        SafeArea(
          child: Column(
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Color(0xFF0A0E1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new,
                            color: Color(0xFFF0F4FF), size: 16),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        "PROFILE",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                          color: Color(0xFF0A0E1A),
                        ),
                      ),
                    ),
                    if (!_isEditing)
                      GestureDetector(
                        onTap: () => setState(() => _isEditing = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Color(0xFF0A0E1A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.edit, color: Color(0xFFF0F4FF), size: 14),
                              SizedBox(width: 6),
                              Text(
                                "EDIT",
                                style: TextStyle(
                                  color: Color(0xFFF0F4FF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => setState(() {
                              _isEditing = false;
                              _nameController.text = widget.username;
                              _base64Image = widget.base64Image;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Color(0xFF0A0E1A).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                "CANCEL",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  color: Color(0x8A0A0E1A),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _isSaving ? null : _saveEdits,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Color(0xFF0A0E1A),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          color: Color(0xFFF0F4FF),
                                          strokeWidth: 2),
                                    )
                                  : const Text(
                                      "SAVE",
                                      style: TextStyle(
                                        color: Color(0xFFF0F4FF),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 24),

                      // Avatar
                      GestureDetector(
                        onTap: _isEditing ? _pickImage : null,
                        child: Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: const Color(0xFFF0F4FF),
                                    width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFF0F4FF)
                                        .withValues(alpha: 0.5),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: _buildAvatar(radius: 56),
                            ),
                            if (_isEditing)
                              Positioned(
                                bottom: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF0A0E1A),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.camera_alt,
                                      color: Color(0xFFF0F4FF), size: 14),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Name field / display
                      _isEditing
                          ? _profileTextField(
                              controller: _nameController,
                              label: "Full Name",
                              icon: Icons.person_outline_rounded,
                            )
                          : _profileInfoTile(
                              label: "NAME",
                              value: widget.username.isNotEmpty
                                  ? widget.username
                                  : "Not set",
                              icon: Icons.person_outline_rounded,
                            ),

                      const SizedBox(height: 12),

                      // Email — always read only
                      _profileInfoTile(
                        label: "EMAIL",
                        value: widget.email.isNotEmpty
                            ? widget.email
                            : "Not set",
                        icon: Icons.alternate_email_rounded,
                        locked: true,
                      ),

                      const SizedBox(height: 12),

                      // Account type badge
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Color(0xFF0A0E1A),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F4FF)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.verified_outlined,
                                color: Color(0xFFF0F4FF),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "ACCOUNT STATUS",
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  "Active — data is being saved",
                                  style: TextStyle(
                                    color: Color(0xFFF0F4FF),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _profileInfoTile({
    required String label,
    required String value,
    required IconData icon,
    bool locked = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F4FF), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Color(0x8A0A0E1A)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: Color(0x610A0E1A),
                    )),
                const SizedBox(height: 3),
                Text(value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xDD0A0E1A),
                    )),
              ],
            ),
          ),
          if (locked)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Color(0xFF0A0E1A).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                "LOCKED",
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: Color(0x610A0E1A)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _profileTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(
          fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF0A0E1A)),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Color(0x8A0A0E1A), size: 20),
        labelText: label,
        labelStyle: const TextStyle(
            color: Color(0x610A0E1A), fontSize: 14, fontWeight: FontWeight.w500),
        filled: true,
        fillColor: const Color(0xFFF0F4FF).withValues(alpha: 0.2),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              const BorderSide(color: Color(0xFFF0F4FF), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              const BorderSide(color: Color(0xFFF0F4FF), width: 2),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  ANONYMOUS VIEW — 3 stages
  // ─────────────────────────────────────────────
  Widget _buildAnonView() {
    return Stack(
      children: [
        Positioned(
          top: -80,
          right: -60,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF0F4FF).withValues(alpha: 0.35),
            ),
          ),
        ),
        Positioned(
          bottom: -120,
          left: -80,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF0F4FF).withValues(alpha: 0.15),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              // Back button
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Color(0xFF0A0E1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new,
                            color: Color(0xFFF0F4FF), size: 16),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: CurvedAnimation(
                        parent: anim, curve: Curves.easeOut),
                    child: child,
                  ),
                  child: switch (_anonStage) {
                    'join' => _anonJoinView(),
                    'returning' => _anonReturningView(),
                    'awaiting_link' => _anonAwaitingView(),
                    _ => const SizedBox.shrink(),
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Stage 1 — Join form
  Widget _anonJoinView() {
    return SingleChildScrollView(
      key: const ValueKey('join'),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _anonHeader(
            tag: "CREATE ACCOUNT",
            title: "START\nSAVING.",
            subtitle:
                "Add your details and your Vox data will be saved from this point forward.",
          ),
          const SizedBox(height: 36),

          // Avatar picker
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFFF0F4FF), width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF0F4FF).withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 52,
                      backgroundColor:
                          const Color(0xFFF0F4FF).withValues(alpha: 0.1),
                      backgroundImage: _base64Image != null
                          ? MemoryImage(base64Decode(_base64Image!))
                          : null,
                      child: _base64Image == null
                          ? const Icon(Icons.camera_alt_outlined,
                              color: Color(0x420A0E1A), size: 28)
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                          color: Color(0xFF0A0E1A), shape: BoxShape.circle),
                      child: const Icon(Icons.edit,
                          color: Color(0xFFF0F4FF), size: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          _anonTextField(
            controller: _nameController,
            label: "Full Name",
            icon: Icons.person_outline_rounded,
          ),
          _anonTextField(
            controller: _emailController,
            label: "Email Address",
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 24),

          _anonButton(
            label: "SAVE & START",
            isLoading: _anonLoading,
            onTap: _onAnonSaveTapped,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // Stage 2 — Returning user
  Widget _anonReturningView() {
    return SingleChildScrollView(
      key: const ValueKey('returning'),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _anonHeader(
            tag: "HOLD ON",
            title: "WE KNOW\nTHIS EMAIL.",
            subtitle: "Looks like you've used Vox before. Want your history back?",
          ),
          const SizedBox(height: 40),

          // Email chip
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: const Color(0xFFF0F4FF), width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                      color: Color(0xFF0A0E1A), shape: BoxShape.circle),
                  child: const Icon(Icons.mail_outline_rounded,
                      color: Color(0xFFF0F4FF), size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("YOUR EMAIL",
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                              color: Color(0x610A0E1A))),
                      const SizedBox(height: 3),
                      Text(_emailController.text.trim(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Color(0xDD0A0E1A)),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Color(0xFF0A0E1A).withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.touch_app_rounded,
                    size: 15, color: Color(0x610A0E1A)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "We'll send a link to your email. Tap it and all your data comes back.",
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0x730A0E1A),
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),

          _anonButton(
            label: "YES, RESTORE MY DATA",
            isLoading: _anonLoading,
            onTap: _sendMagicLink,
          ),
          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton(
              onPressed: _anonLoading ? null : _saveNewAnonProfile,
              style: OutlinedButton.styleFrom(
                foregroundColor: Color(0x8A0A0E1A),
                side: const BorderSide(color: Color(0x1F0A0E1A)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              child: const Text("NO, START FRESH",
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      fontSize: 14)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // Stage 3 — Awaiting link
  Widget _anonAwaitingView() {
    return SingleChildScrollView(
      key: const ValueKey('awaiting'),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _anonHeader(
            tag: "CHECK YOUR EMAIL",
            title: "LINK\nSENT.",
            subtitle:
                "Tap the link in your email and all your Vox data will come back.",
          ),
          const SizedBox(height: 64),

          // Spinning ring
          Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _rotateController,
                    builder: (_, _) => Transform.rotate(
                      angle: _rotateController.value * 2 * pi,
                      child: CustomPaint(
                        size: const Size(100, 100),
                        painter: _SweepRingPainter(),
                      ),
                    ),
                  ),
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4FF).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mail_rounded,
                        color: Color(0xFF0A0E1A), size: 28),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              "Waiting for you to tap the link…",
              style: TextStyle(
                  color: Color(0xFF0A0E1A).withValues(alpha: 0.35),
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ),
          const SizedBox(height: 48),
          Center(
            child: TextButton(
              onPressed: _anonLoading ? null : _sendMagicLink,
              child: const Text("Resend link",
                  style: TextStyle(
                    color: Color(0x730A0E1A),
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0x420A0E1A),
                  )),
            ),
          ),

          // Debug skip
          if (kDebugMode) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('hasProfile', true);
                  if (mounted) Navigator.pop(context);
                },
                child: const Text("⚠ Skip (debug only)",
                    style: TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Shared anon widgets ───────────────────────
  Widget _anonHeader({
    required String tag,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Color(0xFF0A0E1A),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(tag,
              style: const TextStyle(
                  color: Color(0xFFF0F4FF),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2)),
        ),
        const SizedBox(height: 12),
        Text(title,
            style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w900,
                height: 1.05,
                letterSpacing: -1.5,
                color: Color(0xFF0A0E1A))),
        const SizedBox(height: 10),
        Text(subtitle,
            style: const TextStyle(
                color: Color(0x730A0E1A),
                fontWeight: FontWeight.w500,
                fontSize: 14,
                height: 1.5)),
      ],
    );
  }

  Widget _anonTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF0A0E1A)),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Color(0x8A0A0E1A), size: 20),
          labelText: label,
          labelStyle: const TextStyle(
              color: Color(0x610A0E1A),
              fontSize: 14,
              fontWeight: FontWeight.w500),
          filled: true,
          fillColor: const Color(0xFFF0F4FF).withValues(alpha: 0.12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.transparent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide:
                const BorderSide(color: Color(0xFFF0F4FF), width: 2),
          ),
        ),
      ),
    );
  }

  Widget _anonButton({
    required String label,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFF0A0E1A),
          foregroundColor: const Color(0xFFF0F4FF),
          disabledBackgroundColor: Color(0x8A0A0E1A),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18)),
          elevation: 6,
          shadowColor: Color(0xFF0A0E1A).withValues(alpha: 0.3),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Color(0xFFF0F4FF), strokeWidth: 2.5))
            : Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    fontSize: 14)),
      ),
    );
  }
}

// ── Sweep ring painter ────────────────────────
class _SweepRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: size.width / 2 - 4);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = SweepGradient(
        colors: [
          const Color(0xFFF0F4FF).withValues(alpha: 0),
          const Color(0xFFF0F4FF),
        ],
      ).createShader(rect);
    canvas.drawArc(rect, 0, pi * 1.8, false, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}