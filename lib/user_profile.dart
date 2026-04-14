import 'dart:convert';
//import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
//  COLORS
// ─────────────────────────────────────────────
class VoxColors {
  static const Color white = Color(0xFFFFFFFF);
  static const Color yellow = Color(0xFFFFD700);
  static const Color black = Color(0xFF000000);
}

// ─────────────────────────────────────────────
//  ENTRY POINT
// ─────────────────────────────────────────────
class UserProfilePage extends StatefulWidget {
  final bool isEditingMode; // New parameter to distinguish between signup and edit mode
  
  const UserProfilePage({
    super.key,
    this.isEditingMode = false,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  String _stage = 'form';
  bool _isEditingMode = false;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String? _base64Image;
  bool _isLoading = false;
  bool _googleLoading = false;
  bool _isSwitchingEmail = false;
  bool _canSwitchEmail = false;
  String? _currentEmail;
  String? _currentName;
  String? _currentPhotoBase64;

  // Google Sign-In instance
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
  );

  @override
  void initState() {
    super.initState();
    _isEditingMode = widget.isEditingMode;
    _ensureAuth();
    _loadCurrentUserData();
    _evaluateSwitchableEmail();
  }

  Future<void> _loadCurrentUserData() async {
    if (!_isEditingMode) return;
    
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (doc.exists) {
          final data = doc.data();
          setState(() {
            _currentEmail = data?['email'] ?? user.email;
            _currentName = data?['username'] ?? user.displayName;
            _currentPhotoBase64 = data?['photoBase64'];
            _nameController.text = _currentName ?? '';
            _emailController.text = _currentEmail ?? '';
            _base64Image = _currentPhotoBase64;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading user data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _evaluateSwitchableEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null &&
        !user.isAnonymous &&
        (user.email?.isNotEmpty ?? false)) {
      setState(() {
        _canSwitchEmail = true;
      });
    }
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

  Future<void> _requestEmailSwitch() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch Email Address'),
        content: const Text(
          'Changing your email will update your profile and all associated data will be migrated to the new email. '
          'You will need to verify the new email address.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      setState(() {
        _isSwitchingEmail = true;
        _stage = 'form';
        _emailController.clear();
      });
      _showSnack('Enter your new email address and tap Save to apply.');
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
    final currentUser = FirebaseAuth.instance.currentUser;

    // Handle email switching in edit mode
    if (_isEditingMode && _isSwitchingEmail && currentUser != null && !currentUser.isAnonymous) {
      if (email.isEmpty) {
        _showSnack("Please enter the new email address.");
        return;
      }
      if (!email.contains('@') || !email.contains('.')) {
        _showSnack("Please enter a valid email address");
        return;
      }
      await _initiateEmailSwitch(currentUser.uid, email);
      return;
    }

    // Handle profile update in edit mode
    if (_isEditingMode && currentUser != null && !currentUser.isAnonymous) {
      await _updateExistingProfile(currentUser.uid, name, email);
      return;
    }

    // Original sign-up flow
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
        if (currentUser != null &&
            !currentUser.isAnonymous &&
            _isSwitchingEmail) {
          await _initiateEmailSwitch(currentUser.uid, email);
        } else {
          setState(() => _stage = 'returning');
        }
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

  Future<void> _updateExistingProfile(String uid, String name, String email) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'username': name,
        'email': email,
        'photoBase64': _base64Image ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userEmail', email);
      await prefs.setString('userName', name);
      
      _showSnack("Profile updated successfully!");
      
      if (!mounted) return;
      Navigator.of(context).pop(); // Go back to previous screen
    } catch (e) {
      _showSnack("Failed to update profile: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initiateEmailSwitch(String uid, String newEmail) async {
    // Check if email already exists
    final existingUser = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: newEmail)
        .limit(1)
        .get();
    
    if (existingUser.docs.isNotEmpty && existingUser.docs.first.id != uid) {
      _showSnack("This email is already registered to another account.");
      return;
    }
    
    final warning = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ Important Warning'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Switching your email will:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('• Change your login credentials'),
            Text('• Migrate all your data to the new email'),
            Text('• Require email verification'),
            Text('• Sign you out after completion'),
            SizedBox(height: 12),
            Text(
              'You will need to verify the new email address to continue using your account.',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('I Understand, Continue'),
          ),
        ],
      ),
    );
    
    if (warning != true) return;
    
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("No user found");
      
      // Store pending email change in Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'pendingEmail': newEmail,
        'emailChangeRequestedAt': FieldValue.serverTimestamp(),
      });
      
      // Send verification email
      await user.sendEmailVerification();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pendingEmailChange', newEmail);
      
      _showSnack("Verification email sent to $newEmail. Please verify to complete the switch.");
      
      if (!mounted) return;
      
      // Show verification waiting screen
      setState(() {
        _stage = 'awaiting_link';
        _isSwitchingEmail = false;
      });
      
    } catch (e) {
      _showSnack("Failed to initiate email switch: $e");
      setState(() => _isLoading = false);
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
      Navigator.of(context, rootNavigator: true).pushReplacementNamed('/home');
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
      barrierColor: Color(0xFF0A0E1A).withValues(alpha: 0.6),
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
                  color: Color(0xFF0A0E1A),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "All your previous Vox activity — notes, library files, and profile — linked to this email will be permanently deleted. This cannot be undone.",
                style: TextStyle(
                  color: Color(0x8A0A0E1A),
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
                  color: Colors.red.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
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
                        foregroundColor: Color(0xFF0A0E1A),
                        side: const BorderSide(color: Color(0x420A0E1A)),
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

      // Check for pending email change
      final pendingEmail = prefs.getString('pendingEmailChange');
      if (pendingEmail != null && !isFreshStart) {
        // Handle email switch completion
        await _completeEmailSwitch(user.uid, pendingEmail);
        await prefs.remove('pendingEmailChange');
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pushReplacementNamed('/home');
        return;
      }

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
      Navigator.of(context, rootNavigator: true).pushReplacementNamed('/home');
    } catch (e) {
      _showSnack("Error completing sign-in: $e");
    }
  }

  Future<void> _completeEmailSwitch(String uid, String newEmail) async {
    try {
      // Update the user document with new email
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'email': newEmail,
        'pendingEmail': FieldValue.delete(),
        'emailChangeRequestedAt': FieldValue.delete(),
        'emailVerified': true,
      });
      
      // Update all notes and library entries that use email as identifier
      final notes = await FirebaseFirestore.instance
          .collection('notes')
          .where('userId', isEqualTo: uid)
          .get();
      for (final note in notes.docs) {
        await note.reference.update({'userEmail': newEmail});
      }
      
      final library = await FirebaseFirestore.instance
          .collection('library')
          .where('userId', isEqualTo: uid)
          .get();
      for (final file in library.docs) {
        await file.reference.update({'userEmail': newEmail});
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userEmail', newEmail);
      
      _showSnack("Email successfully changed to $newEmail!");
    } catch (e) {
      _showSnack("Error completing email switch: $e");
      rethrow;
    }
  }

  // ─────────────────────────────────────────────
  //  GOOGLE SIGN-IN
  // ─────────────────────────────────────────────
  Future<void> _handleGoogleSignIn() async {
    setState(() => _googleLoading = true);
    try {
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
        final googleUser = await _googleSignIn.signIn();
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
      Navigator.of(context, rootNavigator: true).pushReplacementNamed('/home');
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
      appBar: _isEditingMode ? AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0A0E1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: Color(0xFF0A0E1A),
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ) : null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
        child: () {
          switch (_stage) {
            case 'form':
              return _ProfileFormView(
                key: const ValueKey('form'),
                nameController: _nameController,
                emailController: _emailController,
                base64Image: _base64Image,
                isLoading: _isLoading,
                googleLoading: _googleLoading,
                isSwitchingEmail: _isSwitchingEmail,
                canSwitchEmail: _canSwitchEmail && _isEditingMode,
                isEditingMode: _isEditingMode,
                currentEmail: _currentEmail,
                onPickImage: _pickImage,
                onSave: _onSaveTapped,
                onGoogleSignIn: _handleGoogleSignIn,
                onSwitchEmail: _requestEmailSwitch,
              );
            case 'returning':
              return _ReturningUserView(
                key: const ValueKey('returning'),
                email: _emailController.text.trim(),
                onConfirm: () => _sendMagicLink(isFreshStart: false),
                onStartFresh: _onStartFreshTapped,
                isLoading: _isLoading,
              );
            case 'awaiting_link':
              return _AwaitingLinkView(
                key: const ValueKey('awaiting_link'),
                email: _emailController.text.trim(),
                onResend: () => _sendMagicLink(isFreshStart: false),
                onVerified: _onMagicLinkVerified,
              );
            default:
              return const SizedBox.shrink();
          }
        }(),
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
  final bool isSwitchingEmail;
  final VoidCallback onPickImage;
  final VoidCallback onSave;
  final VoidCallback onGoogleSignIn;
  final bool canSwitchEmail;
  final bool isEditingMode;
  final String? currentEmail;
  final VoidCallback onSwitchEmail;

  const _ProfileFormView({
    super.key,
    required this.nameController,
    required this.emailController,
    required this.base64Image,
    required this.isLoading,
    required this.googleLoading,
    required this.isSwitchingEmail,
    required this.canSwitchEmail,
    required this.isEditingMode,
    required this.currentEmail,
    required this.onPickImage,
    required this.onSave,
    required this.onGoogleSignIn,
    required this.onSwitchEmail,
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
                  color: Color(0xFF0A0E1A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Color(0xFF0A0E1A),
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
                color: Color(0x8A0A0E1A),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: VoxColors.yellow.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: Color(0x8A0A0E1A),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "You can always add your details later from the menu.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0x8A0A0E1A),
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
                      foregroundColor: Color(0xFF0A0E1A),
                      side: const BorderSide(color: Color(0x420A0E1A)),
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
                          Navigator.of(
                            context,
                            rootNavigator: true,
                          ).pushReplacementNamed('/home');
                        }
                      } catch (e) {
                        debugPrint("Guest sign-in error: $e");
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF0A0E1A),
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
          if (!isEditingMode)
            const _VoxHeader(
              tag: "WELCOME",
              title: "JOIN\nTHE VOX.",
              subtitle: "Set up your profile to get started.",
            )
          else
            const SizedBox(height: 20),
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
                          color: VoxColors.yellow.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 52,
                      backgroundColor: VoxColors.yellow.withValues(alpha: 0.1),
                      backgroundImage: base64Image != null
                          ? MemoryImage(base64Decode(base64Image!))
                          : null,
                      child: base64Image == null
                          ? const Icon(
                              Icons.camera_alt_outlined,
                              color: Color(0x420A0E1A),
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
                        color: Color(0xFF0A0E1A),
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
            label: isEditingMode && !isSwitchingEmail 
                ? "Email Address (tap 'Switch Email' to change)" 
                : "Email Address",
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            enabled: !(isEditingMode && !isSwitchingEmail),
          ),
          const SizedBox(height: 24),
          _VoxButton(
            label: isEditingMode 
                ? (isSwitchingEmail ? "SAVE NEW EMAIL" : "UPDATE PROFILE")
                : "SAVE PROFILE",
            isLoading: isLoading,
            onTap: onSave,
          ),
          const SizedBox(height: 12),
          if (canSwitchEmail && isEditingMode && !isSwitchingEmail)
            Center(
              child: TextButton(
                onPressed: onSwitchEmail,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.switch_account_rounded,
                      size: 16,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Switch Email",
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (isEditingMode && currentEmail != null && !isSwitchingEmail)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Current email: $currentEmail",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (!isEditingMode) ...[
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
                    color: Color(0x610A0E1A),
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0x420A0E1A),
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

// ─────────────────────────────────────────────
//  RETURNING USER VIEW
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
            tag: "WELCOME BACK",
            title: "YOU'RE\nALREADY HERE.",
            subtitle: "Looks like you've voxed before.",
          ),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: VoxColors.yellow.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: VoxColors.yellow.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.mark_email_read_rounded,
                      color: VoxColors.yellow,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        email,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xDD0A0E1A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  "What would you like to do?",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "We found an existing profile with this email.",
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0x8A0A0E1A),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                _VoxButton(
                  label: "VERIFY & LOG IN",
                  isLoading: isLoading,
                  onTap: onConfirm,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: onStartFresh,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade200),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: const Text("START FRESH (DELETE OLD DATA)"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  AWAITING LINK VIEW
// ─────────────────────────────────────────────
class _AwaitingLinkView extends StatelessWidget {
  final String email;
  final VoidCallback onResend;
  final VoidCallback onVerified;

  const _AwaitingLinkView({
    super.key,
    required this.email,
    required this.onResend,
    required this.onVerified,
  });

  @override
  Widget build(BuildContext context) {
    return VoxScaffoldWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _VoxHeader(
            tag: "ONE LAST STEP",
            title: "CHECK YOUR\nINBOX.",
            subtitle: "Click the magic link we just sent.",
          ),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF0A0E1A).withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: VoxColors.yellow.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.email_outlined,
                    size: 48,
                    color: VoxColors.yellow,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "We've sent a magic sign-in link to your email. Click it to continue.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0x8A0A0E1A),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                _VoxButton(
                  label: "I'VE CLICKED THE LINK",
                  onTap: onVerified,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: onResend,
                  child: const Text("Resend email"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  HELPER WIDGETS
// ─────────────────────────────────────────────
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: VoxColors.yellow.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              tag,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: VoxColors.yellow,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              height: 1.1,
              color: Color(0xFF0A0E1A),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0x8A0A0E1A),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoxTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool enabled;

  const _VoxTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20, color: Color(0x730A0E1A)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: VoxColors.yellow, width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFF0A0E1A),
          foregroundColor: VoxColors.yellow,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(VoxColors.yellow),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 1,
                ),
              ),
      ),
    );
  }
}

class _DividerRow extends StatelessWidget {
  const _DividerRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Colors.grey.shade300,
              thickness: 1,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "or",
              style: TextStyle(
                color: Color(0x610A0E1A),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: Colors.grey.shade300,
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _GoogleButton({
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton(
        onPressed: isLoading ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Color(0xDD0A0E1A),
          side: BorderSide(color: Colors.grey.shade300),
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/btn_google_signin.png',
                    height: 40,
                    width: 120,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "Continue with Google",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class VoxScaffoldWrapper extends StatelessWidget {
  final Widget child;

  const VoxScaffoldWrapper({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: child,
      ),
    );
  }
}