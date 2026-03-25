import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
//  ENTRY POINT
// ─────────────────────────────────────────────
class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  String _stage = 'form';

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String? _base64Image;
  bool _isLoading = false;
  bool _googleLoading = false;

  @override
  void initState() {
    super.initState();
    _ensureAuth();
  }

  /// Ensure we have at least an anonymous session so we can query Firestore
  Future<void> _ensureAuth() async {
    if (FirebaseAuth.instance.currentUser == null) {
      try {
        await FirebaseAuth.instance.signInAnonymously();
      } catch (e) {
        debugPrint("Silent anon sign-in error: $e");
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  //  SAVE BUTTON — check if email exists first
  // ─────────────────────────────────────────────
  Future<void> _onSaveTapped() async {
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

    setState(() => _isLoading = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (snapshot.docs.isNotEmpty) {
        setState(() => _stage = 'returning');
      } else {
        await _saveNewUserAndGoHome();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack("Error: $e");
      }
    }
  }

  // ─────────────────────────────────────────────
  //  NEW USER — sign in anonymously, save profile
  // ─────────────────────────────────────────────
  Future<void> _saveNewUserAndGoHome() async {
    setState(() => _isLoading = true);
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        final cred = await FirebaseAuth.instance.signInAnonymously();
        user = cred.user;
      }

      final uid = user!.uid;
      final email = _emailController.text.trim();
      final name = _nameController.text.trim();

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'username': name,
        'email': email,
        'photoBase64': _base64Image ?? '',
        'photoUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
        'userId': uid,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasProfile', true);
      await prefs.setString('userEmail', email);
      await prefs.setString('userName', name);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true)
          .pushReplacementNamed('/home');
    } catch (e) {
      _showSnack("Error saving profile: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─────────────────────────────────────────────
  //  SEND MAGIC LINK
  // ─────────────────────────────────────────────
  Future<void> _sendMagicLink({bool isFreshStart = false}) async {
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();

      final acs = ActionCodeSettings(
        url:
            'https://vox-application-76ecd.firebaseapp.com/verify?email=$email',
        handleCodeInApp: true,
        androidPackageName: 'com.example.voxapplication',
        androidInstallApp: true,
        androidMinimumVersion: '21',
        iOSBundleId: 'com.example.voxapplication',
      );

      await FirebaseAuth.instance.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: acs,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pendingEmailLink', email);
      await prefs.setString('pendingName', _nameController.text.trim());
      await prefs.setString('pendingPhoto', _base64Image ?? '');
      await prefs.setBool('pendingIsFreshStart', isFreshStart);

      if (!mounted) return;
      setState(() => _stage = 'awaiting_link');
    } catch (e) {
      _showSnack("Error sending link: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─────────────────────────────────────────────
  //  RETURNING USER — "START FRESH" WARNING
  // ─────────────────────────────────────────────
  Future<void> _onStartFreshTapped() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "WARNING",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "This will delete\nyour old data.",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  height: 1.1,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "All your previous Vox activity — notes, library files, and profile — linked to this email will be permanently deleted. This cannot be undone.",
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: Colors.red,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "You'll verify your email to confirm this action.",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black,
                        side: const BorderSide(color: Colors.black26),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        "Go Back",
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Delete & Reset",
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    await _sendMagicLink(isFreshStart: true);
  }

  // ─────────────────────────────────────────────
  //  MAGIC LINK VERIFIED
  // ─────────────────────────────────────────────
  Future<void> _onMagicLinkVerified() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final isFreshStart = prefs.getBool('pendingIsFreshStart') ?? false;
      final email = user.email ?? prefs.getString('pendingEmailLink') ?? '';
      final name = prefs.getString('pendingName') ?? '';
      final photo = prefs.getString('pendingPhoto') ?? '';

      if (isFreshStart) {
        final oldUsers = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: email)
            .get();
        for (final doc in oldUsers.docs) {
          final notes = await FirebaseFirestore.instance
              .collection('notes')
              .where('userId', isEqualTo: doc.id)
              .get();
          for (final note in notes.docs) {
            await note.reference.delete();
          }
          final library = await FirebaseFirestore.instance
              .collection('library')
              .where('userId', isEqualTo: doc['email'])
              .get();
          for (final file in library.docs) {
            await file.reference.delete();
          }
          await doc.reference.delete();
        }

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'username': name.isNotEmpty ? name : user.displayName ?? '',
          'email': email,
          'photoBase64': photo,
          'photoUrl': user.photoURL ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'userId': user.uid,
        });
      } else {
        final oldUsers = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: email)
            .get();

        String? oldUid;
        Map<String, dynamic>? oldData;
        if (oldUsers.docs.isNotEmpty) {
          oldUid = oldUsers.docs.first.id;
          oldData = oldUsers.docs.first.data();
          await oldUsers.docs.first.reference.delete();
        }

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'username': oldData?['username'] ?? name,
          'email': email,
          'photoBase64': oldData?['photoBase64'] ?? photo,
          'photoUrl': oldData?['photoUrl'] ?? user.photoURL ?? '',
          'createdAt': oldData?['createdAt'] ?? FieldValue.serverTimestamp(),
          'userId': user.uid,
        });

        if (oldUid != null && oldUid != user.uid) {
          final notes = await FirebaseFirestore.instance
              .collection('notes')
              .where('userId', isEqualTo: oldUid)
              .get();
          for (final note in notes.docs) {
            await note.reference.update({'userId': user.uid});
          }
        }
      }

      await prefs.setBool('hasProfile', true);
      await prefs.setString('userEmail', email);
      await prefs.setString('userName', prefs.getString('pendingName') ?? '');
      await prefs.remove('pendingEmailLink');
      await prefs.remove('pendingName');
      await prefs.remove('pendingPhoto');
      await prefs.remove('pendingIsFreshStart');

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true)
          .pushReplacementNamed('/home');
    } catch (e) {
      _showSnack("Error completing sign-in: $e");
    }
  }

  // ─────────────────────────────────────────────
  //  GOOGLE SIGN-IN — FIX: sign out anon first
  // ─────────────────────────────────────────────
  Future<void> _handleGoogleSignIn() async {
    setState(() => _googleLoading = true);
    try {
      // ── Sign out anonymous session first so it doesn't block Google auth ──
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && currentUser.isAnonymous) {
        await FirebaseAuth.instance.signOut();
      }

      UserCredential result;

      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();
        googleProvider.setCustomParameters({'prompt': 'select_account'});
        result = await FirebaseAuth.instance.signInWithPopup(googleProvider);
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          setState(() => _googleLoading = false);
          return;
        }
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        result = await FirebaseAuth.instance.signInWithCredential(credential);
      }

      final user = result.user!;

      // Save to Firestore if first time
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'username': user.displayName ?? '',
          'email': user.email ?? '',
          'photoBase64': '',
          'photoUrl': user.photoURL ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'userId': user.uid,
        });
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasProfile', true);
      await prefs.setString('userEmail', user.email ?? '');
      await prefs.setString('userName', user.displayName ?? '');

      if (!mounted) return;
      // ── FIX: use rootNavigator to ensure navigation works after auth ──
      Navigator.of(context, rootNavigator: true)
          .pushReplacementNamed('/home');
    } catch (e) {
      _showSnack("Google sign-in failed: $e");
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  // ─────────────────────────────────────────────
  //  IMAGE PICKER
  // ─────────────────────────────────────────────
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

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF333333),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VoxColors.white,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
        child: switch (_stage) {
          'form' => _ProfileFormView(
            key: const ValueKey('form'),
            nameController: _nameController,
            emailController: _emailController,
            base64Image: _base64Image,
            isLoading: _isLoading,
            googleLoading: _googleLoading,
            onPickImage: _pickImage,
            onSave: _onSaveTapped,
            onGoogleSignIn: _handleGoogleSignIn,
          ),
          'returning' => _ReturningUserView(
            key: const ValueKey('returning'),
            email: _emailController.text.trim(),
            onConfirm: () => _sendMagicLink(isFreshStart: false),
            onStartFresh: _onStartFreshTapped,
            isLoading: _isLoading,
          ),
          'awaiting_link' => _AwaitingLinkView(
            key: const ValueKey('awaiting_link'),
            email: _emailController.text.trim(),
            onResend: () => _sendMagicLink(isFreshStart: false),
            onVerified: _onMagicLinkVerified,
          ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  STAGE 1 — Profile form
// ─────────────────────────────────────────────
class _ProfileFormView extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController emailController;
  final String? base64Image;
  final bool isLoading;
  final bool googleLoading;
  final VoidCallback onPickImage;
  final VoidCallback onSave;
  final VoidCallback onGoogleSignIn;

  const _ProfileFormView({
    super.key,
    required this.nameController,
    required this.emailController,
    required this.base64Image,
    required this.isLoading,
    required this.googleLoading,
    required this.onPickImage,
    required this.onSave,
    required this.onGoogleSignIn,
  });

  void _showGuestWarning(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        padding: const EdgeInsets.all(28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: VoxColors.yellow,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Text(
                  "Heads up.",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              "Without an account, nothing you do in Vox will be saved. If you close the app your activity is gone forever.",
              style: TextStyle(
                color: Colors.black54,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: VoxColors.yellow.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: Colors.black54,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "You can always add your details later from the menu.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.black26),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text(
                      "Add Email",
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      try {
                        await FirebaseAuth.instance.signInAnonymously();
                        if (context.mounted) {
                          Navigator.of(context, rootNavigator: true)
                              .pushReplacementNamed('/home');
                        }
                      } catch (e) {
                        debugPrint("Guest sign-in error: $e");
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: VoxColors.yellow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      elevation: 0,
                    ),
                    child: const Text(
                      "Continue Anyway",
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return VoxScaffoldWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _VoxHeader(
            tag: "WELCOME",
            title: "JOIN\nTHE VOX.",
            subtitle: "Set up your profile to get started.",
          ),
          const SizedBox(height: 36),

          // Avatar picker
          Center(
            child: GestureDetector(
              onTap: onPickImage,
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: VoxColors.yellow, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: VoxColors.yellow.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 52,
                      backgroundColor: VoxColors.yellow.withOpacity(0.1),
                      backgroundImage: base64Image != null
                          ? MemoryImage(base64Decode(base64Image!))
                          : null,
                      child: base64Image == null
                          ? const Icon(
                              Icons.camera_alt_outlined,
                              color: Colors.black26,
                              size: 28,
                            )
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit,
                        color: VoxColors.yellow,
                        size: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          _VoxTextField(
            controller: nameController,
            label: "Full Name",
            icon: Icons.person_outline_rounded,
          ),
          _VoxTextField(
            controller: emailController,
            label: "Email Address",
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 24),
          _VoxButton(
            label: "SAVE PROFILE",
            isLoading: isLoading,
            onTap: onSave,
          ),
          const SizedBox(height: 24),
          _DividerRow(),
          const SizedBox(height: 24),
          _GoogleButton(isLoading: googleLoading, onTap: onGoogleSignIn),
          const SizedBox(height: 16),
          _DividerRow(),
          const SizedBox(height: 16),

          Center(
            child: TextButton(
              onPressed: () => _showGuestWarning(context),
              child: const Text(
                "Continue without account",
                style: TextStyle(
                  color: Colors.black38,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.black26,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  STAGE 2 — Returning user
// ─────────────────────────────────────────────
class _ReturningUserView extends StatelessWidget {
  final String email;
  final VoidCallback onConfirm;
  final VoidCallback onStartFresh;
  final bool isLoading;

  const _ReturningUserView({
    super.key,
    required this.email,
    required this.onConfirm,
    required this.onStartFresh,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return VoxScaffoldWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _VoxHeader(
            tag: "HOLD ON",
            title: "WE KNOW\nTHIS EMAIL.",
            subtitle:
                "Looks like you've used Vox before.\nWant your history back?",
          ),
          const SizedBox(height: 48),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: VoxColors.yellow.withOpacity(0.2),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: VoxColors.yellow, width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mail_outline_rounded,
                    color: VoxColors.yellow,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "YOUR EMAIL",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: Colors.black38,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        email,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.touch_app_rounded, size: 15, color: Colors.black38),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "We'll send a link to your email. Tap it and your profile, notes, and library all come back.",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          _VoxButton(
            label: "YES, RESTORE MY DATA",
            isLoading: isLoading,
            onTap: onConfirm,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton(
              onPressed: isLoading ? null : onStartFresh,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black54,
                side: const BorderSide(color: Colors.black12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text(
                "NO, START FRESH",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  STAGE 3 — Awaiting magic link
// ─────────────────────────────────────────────
class _AwaitingLinkView extends StatefulWidget {
  final String email;
  final Future<void> Function() onResend;
  final Future<void> Function() onVerified;

  const _AwaitingLinkView({
    super.key,
    required this.email,
    required this.onResend,
    required this.onVerified,
  });

  @override
  State<_AwaitingLinkView> createState() => _AwaitingLinkViewState();
}

class _AwaitingLinkViewState extends State<_AwaitingLinkView>
    with SingleTickerProviderStateMixin {
  bool _resendLoading = false;
  late AnimationController _rotateController;

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Listen for real (non-anonymous) sign-in
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && !user.isAnonymous && mounted) {
        widget.onVerified();
      }
    });
  }

  @override
  void dispose() {
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VoxScaffoldWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _VoxHeader(
            tag: "CHECK YOUR EMAIL",
            title: "LINK\nSENT.",
            subtitle: "Tap the link in your email to verify and continue.",
          ),
          const SizedBox(height: 32),

          // Email chip
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: VoxColors.yellow.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: VoxColors.yellow.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.mail_outline_rounded,
                  color: Colors.black54,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.email,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 48),

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
                    builder: (_, __) => Transform.rotate(
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
                      color: VoxColors.yellow.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mail_rounded,
                      color: Colors.black,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              "Waiting for you to tap the link…",
              style: TextStyle(
                color: Colors.black.withOpacity(0.35),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 48),

          Center(
            child: _resendLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.black38,
                      strokeWidth: 2,
                    ),
                  )
                : TextButton(
                    onPressed: () async {
                      setState(() => _resendLoading = true);
                      await widget.onResend();
                      if (mounted) setState(() => _resendLoading = false);
                    },
                    child: const Text(
                      "Resend link",
                      style: TextStyle(
                        color: Colors.black45,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.black26,
                      ),
                    ),
                  ),
          ),

          if (kDebugMode) ...[
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('hasProfile', true);
                  if (context.mounted) {
                    Navigator.of(context, rootNavigator: true)
                        .pushReplacementNamed('/home');
                  }
                },
                child: const Text(
                  "⚠ Skip (debug only)",
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SweepRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: size.width / 2 - 4,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = SweepGradient(
        colors: [VoxColors.yellow.withOpacity(0), VoxColors.yellow],
      ).createShader(rect);
    canvas.drawArc(rect, 0, pi * 1.8, false, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────
//  SHARED DESIGN SYSTEM
// ─────────────────────────────────────────────
class VoxColors {
  static const yellow = Color(0xFFF3E5AB);
  static const white = Colors.white;
}

class VoxScaffoldWrapper extends StatelessWidget {
  final Widget child;
  const VoxScaffoldWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
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
              color: VoxColors.yellow.withOpacity(0.35),
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
              color: VoxColors.yellow.withOpacity(0.15),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 64),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _VoxHeader extends StatelessWidget {
  final String tag;
  final String title;
  final String subtitle;
  const _VoxHeader({
    required this.tag,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            tag,
            style: const TextStyle(
              color: VoxColors.yellow,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w900,
            height: 1.05,
            letterSpacing: -1.5,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(
            color: Colors.black45,
            fontWeight: FontWeight.w500,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _VoxTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;
  final bool enabled;

  const _VoxTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        enabled: enabled,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: Colors.black,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.black54, size: 20),
          labelText: label,
          labelStyle: const TextStyle(
            color: Colors.black38,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          filled: true,
          fillColor: enabled
              ? VoxColors.yellow.withOpacity(0.12)
              : Colors.black.withOpacity(0.04),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.transparent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: VoxColors.yellow, width: 2),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.transparent),
          ),
        ),
      ),
    );
  }
}

class _VoxButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  const _VoxButton({
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: VoxColors.yellow,
          disabledBackgroundColor: Colors.black54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 6,
          shadowColor: Colors.black.withOpacity(0.3),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: VoxColors.yellow,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }
}

class _DividerRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(color: Colors.black.withOpacity(0.1), thickness: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            "OR",
            style: TextStyle(
              color: Colors.black.withOpacity(0.3),
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Expanded(
          child: Divider(color: Colors.black.withOpacity(0.1), thickness: 1),
        ),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isLoading;
  const _GoogleButton({required this.onTap, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: isLoading ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black,
          side: BorderSide(color: Colors.black.withOpacity(0.15), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          backgroundColor: Colors.white,
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.black54,
                  strokeWidth: 2,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GoogleLogo(size: 22),
                  SizedBox(width: 12),
                  Text(
                    "Continue with Google",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  final double size;
  const _GoogleLogo({this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    const sw = 0.22;

    void arc(Color color, double start, double sweep) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * (1 - sw / 2)),
        start,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * sw
          ..strokeCap = StrokeCap.butt,
      );
    }

    const pi = 3.1415926535;
    arc(const Color(0xFF4285F4), -pi / 2, pi * 0.5);
    arc(const Color(0xFFEA4335), 0, pi * 0.5);
    arc(const Color(0xFFFBBC05), pi / 2, pi * 0.4);
    arc(const Color(0xFF34A853), pi * 0.9, pi * 0.6);

    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    final barH = r * sw;
    canvas.drawRect(
      Rect.fromLTWH(c.dx, c.dy - barH / 2, r * 0.85, barH),
      barPaint,
    );

    canvas.drawCircle(c, r * (1 - sw), Paint()..color = Colors.white);

    canvas.drawRect(
      Rect.fromLTWH(c.dx, c.dy - barH / 2, r * 0.72, barH),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}