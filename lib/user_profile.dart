import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  COLORS
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class VoxColors {
  static const Color navy = Color(0xFF0A0E1A);
  static const Color blue = Color(0xFF4B9EFF);
  static const Color neonBlue = Color(0xFF4B9EFF);
  static const Color white = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFF4B9EFF);
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  ENTRY POINT
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class UserProfilePage extends StatefulWidget {
  final bool isEditingMode;

  const UserProfilePage({super.key, this.isEditingMode = false});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage>
    with WidgetsBindingObserver {
  // 'form' | 'returning' | 'awaiting_link' | 'verifying'
  String _stage = 'form';
  bool _isEditingMode = false;

  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

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

  // Google Sign-In â€” mobile only
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    serverClientId:
        '650391636557-h799717ovtk7k86d171cd6rcqj68csc4.apps.googleusercontent.com',
  );

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  LIFECYCLE
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  void initState() {
    super.initState();
    _isEditingMode = widget.isEditingMode;
    _ensureAuth();
    _loadCurrentUserData();
    _evaluateSwitchableEmail();
    _initDeepLinks();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _stage == 'awaiting_link') {
      _checkVerificationStatus();
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  DEEP LINKS
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (mounted) _handleIncomingLink(uri);
    });

    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null && mounted) {
      _handleIncomingLink(initialUri);
    }
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    final link = uri.toString();
    if (!FirebaseAuth.instance.isSignInWithEmailLink(link)) return;

    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('pendingEmailLink') ?? '';
    if (email.isEmpty) return;

    if (mounted) setState(() => _stage = 'verifying');
    try {
      await FirebaseAuth.instance.signInWithEmailLink(
        email: email,
        emailLink: link,
      );
      await _onMagicLinkVerified();
    } catch (e) {
      _showSnack('Verification failed: $e');
      if (mounted) setState(() => _stage = 'awaiting_link');
    }
  }

  Future<void> _checkVerificationStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await user.reload();
    if (FirebaseAuth.instance.currentUser?.emailVerified == true) {
      await _onMagicLinkVerified();
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  LOAD / INIT
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _loadCurrentUserData() async {
    if (!_isEditingMode) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists && mounted) {
          final data = doc.data()!;
          setState(() {
            _currentEmail = data['email'] as String? ?? user.email;
            _currentName = data['username'] as String? ?? user.displayName;
            _currentPhotoBase64 = data['photoBase64'] as String?;
            _nameController.text = _currentName ?? '';
            _emailController.text = _currentEmail ?? '';
            _base64Image = _currentPhotoBase64;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _evaluateSwitchableEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous && (user.email?.isNotEmpty ?? false)) {
      if (mounted) setState(() => _canSwitchEmail = true);
    }
  }

  Future<void> _ensureAuth() async {
    if (FirebaseAuth.instance.currentUser == null) {
      try {
        await FirebaseAuth.instance.signInAnonymously();
      } catch (e) {
        debugPrint('Silent anon sign-in error: $e');
      }
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  EMAIL SWITCH
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _requestEmailSwitch() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch Email Address'),
        content: const Text(
          'Changing your email will update your profile. '
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
    if (confirm == true && mounted) {
      setState(() {
        _isSwitchingEmail = true;
        _stage = 'form';
        _emailController.clear();
      });
      _showSnack('Enter your new email address and tap Save to apply.');
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  SAVE / SUBMIT
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _onSaveTapped() async {
    if (_isLoading) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final currentUser = FirebaseAuth.instance.currentUser;

    if (name.isEmpty) {
      _showSnack('Please enter your full name');
      return;
    }

    // â”€â”€ Switching email flow â”€â”€
    if (_isEditingMode &&
        _isSwitchingEmail &&
        currentUser != null &&
        !currentUser.isAnonymous) {
      if (email.isEmpty) {
        _showSnack('Please enter the new email address.');
        return;
      }
      if (!_isValidEmail(email)) {
        _showSnack('Please enter a valid email address.');
        return;
      }
      await _initiateEmailSwitch(currentUser.uid, email);
      return;
    }

    // â”€â”€ Edit existing profile (no email change) â”€â”€
    if (_isEditingMode) {
      await _updateExistingProfile();
      return;
    }

    // â”€â”€ New user onboarding â”€â”€
    if (!_isValidEmail(email)) {
      _showSnack('Please enter a valid email address.');
      return;
    }

    final exists = await _checkEmailExists(email);
    if (!mounted) return;

    if (exists) {
      setState(() => _stage = 'returning');
    } else {
      await _sendMagicLink();
    }
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email);

  /// Returns true if the email already has a Firestore user document.
  /// Avoids the deprecated [fetchSignInMethodsForEmail].
  Future<bool> _checkEmailExists(String email) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Email check error: $e');
      return false;
    }
  }

  Future<void> _updateExistingProfile() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'username': _nameController.text.trim(),
        'photoBase64': _base64Image ?? '',
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', _nameController.text.trim());

      _showSnack('Profile updated successfully!');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showSnack('Error updating profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initiateEmailSwitch(String uid, String newEmail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Email Change'),
        content: Text(
          'A verification link will be sent to $newEmail. '
          'Your account will not be updated until you verify the new address.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Link'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (mounted) setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No user found');

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'pendingEmail': newEmail,
        'emailChangeRequestedAt': FieldValue.serverTimestamp(),
      });

      await user.verifyBeforeUpdateEmail(newEmail);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pendingEmailChange', newEmail);
      await prefs.setString('pendingEmailLink', newEmail);

      _showSnack(
          'Verification email sent to $newEmail. Verify to complete the switch.');
      if (mounted) {
        setState(() {
          _stage = 'awaiting_link';
          _isSwitchingEmail = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      _showSnack('Failed to initiate email switch: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  MAGIC LINK
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _sendMagicLink({bool isFreshStart = false}) async {
    if (_isLoading) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      final name = _nameController.text.trim();
      final photo = _base64Image ?? '';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pendingEmailLink', email);
      await prefs.setString('pendingName', name);
      await prefs.setString('pendingPhoto', photo);
      await prefs.setBool('pendingIsFreshStart', isFreshStart);

      final actionCodeSettings = ActionCodeSettings(
        url: 'https://the-vox-application.firebaseapp.com/verify?email=$email',
        handleCodeInApp: true,
        androidPackageName: 'com.example.voxapplication',
        androidInstallApp: true,
        androidMinimumVersion: '21',
      );

      await FirebaseAuth.instance.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: actionCodeSettings,
      );

      if (mounted) setState(() => _stage = 'awaiting_link');
    } catch (e) {
      debugPrint('Magic Link Error: $e');
      _showSnack('Error sending link: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onStartFreshTapped() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: VoxColors.navy.withValues(alpha: 0.8),
      builder: (ctx) => AlertDialog(
        title: const Text('Start Fresh?'),
        content: const Text(
          'This will delete all existing data linked to this email. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete & Start Fresh'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _sendMagicLink(isFreshStart: true);
  }

  Future<void> _onMagicLinkVerified() async {
    if (_isLoading) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final isFreshStart = prefs.getBool('pendingIsFreshStart') ?? false;
      final email =
          user.email ?? prefs.getString('pendingEmailLink') ?? '';
      final name = prefs.getString('pendingName') ?? '';
      final photo = prefs.getString('pendingPhoto') ?? '';

      // Check for pending email switch
      final DocumentSnapshot<Map<String, dynamic>> userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = userDoc.data();
      final pendingEmail = (userDoc.exists == true && data != null)
          ? data['pendingEmail'] as String?
          : null;

      if (pendingEmail != null && !isFreshStart) {
        await _completeEmailSwitch(user.uid, pendingEmail);
        return;
      }

      final batch = FirebaseFirestore.instance.batch();

      if (isFreshStart) {
        // Delete old data then create fresh
      final oldUsers = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .get();
      for (final doc in oldUsers.docs) {
        final oldUid = doc.id;
        final notes = await FirebaseFirestore.instance
            .collection('notes')
            .where('userId', isEqualTo: oldUid)
            .get();
        for (final n in notes.docs) {
          batch.delete(n.reference);
        }
        final library = await FirebaseFirestore.instance
            .collection('library')
            .where('userId', isEqualTo: oldUid)
            .get();
        for (final f in library.docs) {
          batch.delete(f.reference);
        }
        batch.delete(doc.reference);
      }
        batch.set(
          FirebaseFirestore.instance.collection('users').doc(user.uid),
          {
            'username': name.isNotEmpty ? name : user.displayName ?? '',
            'email': email,
            'photoBase64': photo,
            'photoUrl': user.photoURL ?? '',
            'createdAt': FieldValue.serverTimestamp(),
            'userId': user.uid,
          },
        );
      } else {
        // Returning user â€” migrate old doc to new UID
        final oldUsers = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: email)
            .get();
        String? oldUid;
        Map<String, dynamic>? oldData;
        if (oldUsers.docs.isNotEmpty) {
          oldUid = oldUsers.docs.first.id;
          oldData = oldUsers.docs.first.data();
          batch.delete(oldUsers.docs.first.reference);
        }
        batch.set(
          FirebaseFirestore.instance.collection('users').doc(user.uid),
          {
            'username': oldData?['username'] ?? name,
            'email': email,
            'photoBase64': oldData?['photoBase64'] ?? photo,
            'photoUrl': oldData?['photoUrl'] ?? user.photoURL ?? '',
            'createdAt': oldData?['createdAt'] ?? FieldValue.serverTimestamp(),
            'userId': user.uid,
          },
        );
        if (oldUid != null && oldUid != user.uid) {
          final notes = await FirebaseFirestore.instance
              .collection('notes')
              .where('userId', isEqualTo: oldUid)
              .get();
          for (final n in notes.docs) {
            batch.update(n.reference, {'userId': user.uid});
          }
        }
      }

      await batch.commit();

      await prefs.setBool('hasProfile', true);
      await prefs.setString('userEmail', email);
      await prefs.setString('userName', name);
      await prefs.remove('pendingEmailLink');
      await prefs.remove('pendingName');
      await prefs.remove('pendingPhoto');
      await prefs.remove('pendingIsFreshStart');

      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .pushReplacementNamed('/home');
      }
    } catch (e) {
      _showSnack('Error completing sign-in: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _completeEmailSwitch(String uid, String newEmail) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.update(
        FirebaseFirestore.instance.collection('users').doc(uid),
        {
          'email': newEmail,
          'pendingEmail': FieldValue.delete(),
          'emailChangeRequestedAt': FieldValue.delete(),
          'emailVerified': true,
        },
      );

      final notes = await FirebaseFirestore.instance
          .collection('notes')
          .where('userId', isEqualTo: uid)
          .get();
      for (final n in notes.docs) {
        batch.update(n.reference, {'userEmail': newEmail});
      }

      final library = await FirebaseFirestore.instance
          .collection('library')
          .where('userId', isEqualTo: uid)
          .get();
      for (final f in library.docs) {
        batch.update(f.reference, {'userEmail': newEmail});
      }

      await batch.commit();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userEmail', newEmail);
      await prefs.remove('pendingEmailChange');

      _showSnack('Email successfully changed to $newEmail!');
      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .pushReplacementNamed('/home');
      }
    } catch (e) {
      _showSnack('Error completing email switch: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  GOOGLE SIGN-IN
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _handleGoogleSignIn() async {
    if (_googleLoading) return;
    if (mounted) setState(() => _googleLoading = true);
    try {
      UserCredential? result;

      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        result = await FirebaseAuth.instance.signInWithPopup(googleProvider);
      } else {
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) return; // user cancelled

        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        result = await FirebaseAuth.instance.signInWithCredential(credential);
      }

      final user = result.user;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
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

      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .pushReplacementNamed('/home');
      }
    } catch (e) {
      _showSnack('Google sign-in error: $e');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  IMAGE PICKER
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 400,
    );
    if (image != null) {
      final bytes = await image.readAsBytes();
      if (mounted) setState(() => _base64Image = base64Encode(bytes));
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  HELPERS
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

  void _showGuestWarning() {
    // Capture navigator before opening sheet so context is not stale inside.
    final nav = Navigator.of(context, rootNavigator: true);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.all(28),
        decoration: const BoxDecoration(
          color: VoxColors.navy,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Heads up.",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Without an account, your activity won't be saved.",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text("Add Email"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      try {
                        await FirebaseAuth.instance.signInAnonymously();
                      } catch (e) {
                        debugPrint('Guest sign-in error: $e');
                      }
                      nav.pushReplacementNamed('/home');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VoxColors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text("Continue Anyway"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  BUILD
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    // Non-form stages rendered inside VoxScaffoldWrapper
    if (_stage != 'form') {
      return VoxScaffoldWrapper(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: switch (_stage) {
            'returning' => _ReturningUserView(
                key: const ValueKey('returning'),
                email: _emailController.text.trim(),
                onConfirm: () => _sendMagicLink(),
                onStartFresh: _onStartFreshTapped,
                isLoading: _isLoading,
              ),
            'awaiting_link' => _AwaitingLinkView(
                key: const ValueKey('awaiting_link'),
                email: _emailController.text.trim(),
                onResend: () => _sendMagicLink(),
                onVerified: _onMagicLinkVerified,
                isLoading: _isLoading,
              ),
            'verifying' => const _VerifyingView(key: ValueKey('verifying')),
            _ => const SizedBox.shrink(),
          },
        ),
      );
    }

    return VoxScaffoldWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isEditingMode)
            const _VoxHeader(
              tag: 'WELCOME',
              title: 'JOIN\nTHE VOX.',
              subtitle: 'Set up your profile to get started.',
            )
          else
            const SizedBox(height: 20),
          const SizedBox(height: 36),

          // â”€â”€ Avatar picker â”€â”€
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: VoxColors.blue, width: 3),
                ),
                child: CircleAvatar(
                  radius: 52,
                  backgroundColor: VoxColors.blue.withValues(alpha: 0.1),
                  backgroundImage: _base64Image != null
                      ? _safeMemoryImage(_base64Image!)
                      : null,
                  child: _base64Image == null
                      ? const Icon(Icons.camera_alt_outlined,
                          color: VoxColors.blue, size: 28)
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          _VoxTextField(
            controller: _nameController,
            label: 'Full Name',
            icon: Icons.person_outline,
          ),
          _VoxTextField(
            controller: _emailController,
            label: 'Email Address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            enabled: !_isEditingMode || _isSwitchingEmail,
          ),

          // Switch email button
          if (_canSwitchEmail && _isEditingMode && !_isSwitchingEmail)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton(
                onPressed: _requestEmailSwitch,
                child: const Text(
                  'Switch Email',
                  style: TextStyle(color: VoxColors.blue),
                ),
              ),
            ),

          const SizedBox(height: 32),

          _VoxButton(
            label: _isEditingMode ? 'SAVE PROFILE' : 'GET STARTED',
            isLoading: _isLoading,
            onTap: _onSaveTapped,
          ),

          if (!_isEditingMode) ...[
            const _DividerRow(),
            _GoogleButton(
              isLoading: _googleLoading,
              onTap: _handleGoogleSignIn,
            ),
            const SizedBox(height: 24),
            Center(
              child: TextButton(
                onPressed: _showGuestWarning,
                child: Text(
                  'Continue without account',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  ImageProvider? _safeMemoryImage(String base64) {
    try {
      return MemoryImage(base64Decode(base64));
    } catch (_) {
      return null;
    }
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  SUB-VIEWS
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _VoxHeader(
          tag: 'WELCOME BACK',
          title: "YOU'RE\nALREADY HERE.",
          subtitle: "Looks like you've voxed before.",
        ),
        const SizedBox(height: 48),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),
                _VoxButton(
                  label: 'VERIFY & LOG IN',
                  isLoading: isLoading,
                  onTap: onConfirm,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: onStartFresh,
                  child: const Text(
                    'START FRESH',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VerifyingView extends StatelessWidget {
  const _VerifyingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: VoxColors.blue),
    );
  }
}

class _AwaitingLinkView extends StatelessWidget {
  final String email;
  final VoidCallback onResend;
  final VoidCallback onVerified;
  final bool isLoading;

  const _AwaitingLinkView({
    super.key,
    required this.email,
    required this.onResend,
    required this.onVerified,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _VoxHeader(
          tag: 'ONE LAST STEP',
          title: 'CHECK YOUR\nINBOX.',
          subtitle: 'Click the magic link we just sent.',
        ),
        const SizedBox(height: 48),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                const Icon(Icons.email_outlined,
                    size: 48, color: VoxColors.blue),
                const SizedBox(height: 16),
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "We've sent a magic sign-in link to your email. Click it to continue.",
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                ),
                const SizedBox(height: 32),
                _VoxButton(
                  label: "I'VE CLICKED THE LINK",
                  isLoading: isLoading,
                  onTap: onVerified,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: onResend,
                  child: const Text(
                    'Resend email',
                    style: TextStyle(color: VoxColors.blue),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  SHARED WIDGETS
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _VoxHeader extends StatelessWidget {
  final String tag, title, subtitle;

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
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: VoxColors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              tag,
              style: const TextStyle(
                color: VoxColors.blue,
                fontSize: 10,
                fontWeight: FontWeight.w800,
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
              color: Colors.white,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
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
  final bool enabled;
  final TextInputType? keyboardType;

  const _VoxTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: VoxColors.blue),
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: VoxColors.blue, width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: VoxColors.blue,
          disabledBackgroundColor: VoxColors.blue.withValues(alpha: 0.4),
          minimumSize: const Size(double.infinity, 56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontSize: 15,
                  letterSpacing: 0.5,
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
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.1))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'OR',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.1))),
        ],
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _GoogleButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton(
        onPressed: isLoading ? null : onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: const BorderSide(color: Colors.white24),
        ),
        child: isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                    color: VoxColors.blue, strokeWidth: 2),
              )
            : const Text(
                'Continue with Google',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class VoxScaffoldWrapper extends StatelessWidget {
  final Widget child;

  const VoxScaffoldWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VoxColors.navy,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: child,
        ),
      ),
    );
  }
}
