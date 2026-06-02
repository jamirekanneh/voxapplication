import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart';
import 'services/app_session.dart';
import 'services/auth_session.dart';

enum _SnackTone { neutral, success, error }

/// Web client ID from Firebase (client_type 3) — required for idToken on Android.
const _kGoogleServerClientId =
    '1033671503358-c8dhmiu6henkq7ig0cg8ata4mq24a9af.apps.googleusercontent.com';

String _googleSignInUserMessage(Object e) {
  if (e is GoogleSignInException) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
      case GoogleSignInExceptionCode.interrupted:
      case GoogleSignInExceptionCode.uiUnavailable:
        return '';
      default:
        final m = (e.description ?? '').trim();
        return m.length > 160 ? '${m.substring(0, 157)}…' : (m.isNotEmpty ? m : e.code.name);
    }
  }
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-credential':
        return 'Google could not verify this device. Add your app signing '
            'SHA-1/SHA-256 in Firebase Console, then reinstall and try again.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'account-exists-with-different-credential':
      case 'credential-already-in-use':
        return 'This Google account is already linked elsewhere. Logging into existing profile...';
      case 'operation-not-allowed':
        return 'Google sign-in is disabled for this app. Contact support.';
      default:
        final h = (e.message ?? '').trim();
        return h.length > 120 ? '${h.substring(0, 117)}…' : (h.isNotEmpty ? h : e.code);
    }
  }
  if (e is PlatformException) {
    final code = e.code.toLowerCase();
    final blob = '${e.message ?? ''} ${e.details ?? ''}'.toLowerCase();
    if (code.contains('canceled') ||
        code.contains('cancelled') ||
        blob.contains('12501')) {
      return '';
    }
    if (blob.contains('network') || code.contains('network')) {
      return 'No internet. Check Wi-Fi or mobile data and try again.';
    }
    if (blob.contains('developer_error') ||
        blob.contains('10:') ||
        code == 'sign_in_failed' ||
        code == 'sign_in_required') {
      return 'Google sign-in could not start. Add SHA-1/SHA-256 in Firebase '
          'Console and ensure google-services.json matches this app.';
    }
    final m = (e.message ?? '').trim();
    return m.length > 160 ? '${m.substring(0, 157)}…' : (m.isNotEmpty ? m : e.code);
  }
  final raw = e.toString();
  final low = raw.toLowerCase();
  if (low.contains('canceled') || low.contains('cancelled')) return '';
  if (raw.length > 140) return '${raw.substring(0, 137)}…';
  return raw;
}

// ─────────────────────────────────────────────────────────────
//  ENTRY POINT
// ─────────────────────────────────────────────────────────────
class UserProfilePage extends StatefulWidget {
  final bool isEditingMode;

  const UserProfilePage({super.key, this.isEditingMode = false});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  bool _isEditingMode = false;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;

  String? _base64Image;
  bool _isLoading = false;
  bool _googleLoading = false;
  bool _isSwitchingEmail = false;
  bool _canSwitchEmail = false;
  String? _currentEmail;
  String? _currentName;
  String? _currentPhotoBase64;
  bool _entryGatePending = true;

  @override
  void initState() {
    super.initState();
    _isEditingMode = widget.isEditingMode;
    GoogleSignIn.instance.initialize(serverClientId: _kGoogleServerClientId);
    unawaited(_resolveEntry());
  }

  /// Block sign-in UI until device restore / auth restore finishes (avoids flash).
  Future<void> _resolveEntry() async {
    try {
      if (!widget.isEditingMode) {
        final redirected = await _redirectIfDeviceRecognized();
        if (redirected) return;
      }
      await _ensureAuth();
      if (widget.isEditingMode) {
        await _loadCurrentUserData();
        await _evaluateSwitchableEmail();
      } else {
        await _prefillFromDeviceOrPrefs();
      }
    } finally {
      if (mounted) setState(() => _entryGatePending = false);
    }
  }

  Future<void> _prefillFromDeviceOrPrefs() async {
    final linked = AppSession.lastRestoredDeviceUser ??
        await AppSession.getDeviceLinkedUser(attempts: 2);
    if (linked != null) {
      if (linked.email?.isNotEmpty ?? false) {
        _emailController.text = linked.email!;
      }
      if (linked.username?.isNotEmpty ?? false) {
        _nameController.text = linked.username!;
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('userEmail');
    final name = prefs.getString('userName');
    if (email != null && email.isNotEmpty) _emailController.text = email;
    if (name != null && name.isNotEmpty) _nameController.text = name;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

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
    if (FirebaseAuth.instance.currentUser != null) return;

    final guest = await AuthSession.isExplicitGuestMode();
    if (guest) {
      try {
        await FirebaseAuth.instance.signInAnonymously();
      } catch (e) {
        debugPrint('Silent anon sign-in error: $e');
      }
      return;
    }

    final savedUid = await AuthSession.savedUserId();
    final prefs = await SharedPreferences.getInstance();
    final hasProfile = prefs.getBool('hasProfile') ?? false;

    // Returning device/user: wait for Firebase session — do not create anonymous
    // (anonymous causes Google/email sign-in errors on first try).
    if (savedUid != null || hasProfile) {
      await AuthSession.waitForSignedInUser(
        timeout: const Duration(seconds: 12),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (e) {
      debugPrint('Silent anon sign-in error: $e');
    }
  }

  /// Returns true if navigated away to home (device recognized — skip profile).
  Future<bool> _redirectIfDeviceRecognized() async {
    if (widget.isEditingMode || !mounted) return false;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        await AppSession.markSetupComplete(userId: user.uid);
        if (!mounted) return false;
        Navigator.of(context, rootNavigator: true).pushReplacementNamed('/home');
        return true;
      }

      final linked = await AppSession.recognizeAndPrepareDevice();
      if (linked == null || !mounted) return false;

      Navigator.of(context, rootNavigator: true).pushReplacementNamed('/home');
      return true;
    } catch (e) {
      debugPrint('Device redirect skipped: $e');
      return false;
    }
  }

  Future<void> _reassignCollectionOwner({
    required String collection,
    required String fromUserId,
    required String toUserId,
  }) async {
    if (fromUserId == toUserId) return;
    final snapshot = await FirebaseFirestore.instance
        .collection(collection)
        .where('userId', isEqualTo: fromUserId)
        .get();
    if (snapshot.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'userId': toUserId});
    }
    await batch.commit();
  }

  Future<void> _mergeLegacyDataToCurrentUid(User user) async {
    final email = (user.email ?? '').trim();
    if (email.isEmpty) return;

    final usersRef = FirebaseFirestore.instance.collection('users');
    final sameEmail = await usersRef.where('email', isEqualTo: email).get();
    final currentRef = usersRef.doc(user.uid);

    final merged = <String, dynamic>{
      'email': email,
      'userId': user.uid,
      'lastLoginAt': FieldValue.serverTimestamp(),
    };
    for (final doc in sameEmail.docs) {
      final data = doc.data();
      if ((data['username'] as String?)?.isNotEmpty == true) {
        merged['username'] = data['username'];
      }
      if ((data['photoBase64'] as String?)?.isNotEmpty == true) {
        merged['photoBase64'] = data['photoBase64'];
      }
      if ((data['photoUrl'] as String?)?.isNotEmpty == true) {
        merged['photoUrl'] = data['photoUrl'];
      }
    }
    await currentRef.set(merged, SetOptions(merge: true));

    final legacyOwnerIds = <String>{email};
    for (final doc in sameEmail.docs) {
      if (doc.id != user.uid) legacyOwnerIds.add(doc.id);
    }
    for (final legacyId in legacyOwnerIds) {
      await _reassignCollectionOwner(
        collection: 'notes',
        fromUserId: legacyId,
        toUserId: user.uid,
      );
      await _reassignCollectionOwner(
        collection: 'library',
        fromUserId: legacyId,
        toUserId: user.uid,
      );
      await _reassignCollectionOwner(
        collection: 'custom_commands',
        fromUserId: legacyId,
        toUserId: user.uid,
      );
    }
  }

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
        _emailController.clear();
      });
      _showSnack('Enter your new email address and tap Save to apply.');
    }
  }

  Future<bool?> _promptSyncExistingAccount(String email) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Account found'),
        content: Text(
          'We found an account for $email.\n\n'
          'Do you remember your password and want to sync your data to this device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              _sendPasswordReset();
            },
            child: const Text('Forgot password'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, sync'),
          ),
        ],
      ),
    );
  }

  Future<void> _onSaveTapped() async {
    if (_isLoading) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final currentUser = FirebaseAuth.instance.currentUser;

    if (name.isEmpty) {
      _showSnack('Please enter your full name');
      return;
    }

    if (_isEditingMode && _isSwitchingEmail && currentUser != null && !currentUser.isAnonymous) {
      if (email.isEmpty || !_isValidEmail(email)) {
        _showSnack('Please enter a valid email address.');
        return;
      }
      await _initiateEmailSwitch(currentUser.uid, email);
      return;
    }

    if (_isEditingMode) {
      // The update method below handles the email-as-ID logic
      await _updateExistingProfile(); 
      return;
    }

    if (!_isValidEmail(email)) {
      _showSnack('Please enter a valid email address.');
      return;
    }

    final password = _passwordController.text;
    if (password.length < 6) {
      _showSnack('Password must be at least 6 characters.');
      return;
    }

    if (mounted) setState(() => _isLoading = true);
    try {
      await _createNewAccount(name, email, password);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        if (!mounted) return;
        setState(() => _isLoading = false);
        final sync = await _promptSyncExistingAccount(email);
        if (sync == true && mounted) {
          await _signInReturningUser(password);
        }
      } else {
        _showSnack(_authErrorMessage(e), tone: _SnackTone.error);
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      _showSnack('Error creating account: $e', tone: _SnackTone.error);
      if (mounted) setState(() => _isLoading = false);
    }
  }
  bool _isValidEmail(String email) =>
      RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email);

 Future<void> _createNewAccount(String name, String email, String password) async {
  try {
    UserCredential cred;
    final currentUser = FirebaseAuth.instance.currentUser;

    // 1. Authentication Logic: Handles linking anonymous accounts or creating new ones
    if (currentUser != null && currentUser.isAnonymous) {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      cred = await currentUser.linkWithCredential(credential);
    } else {
      cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    }

    final user = cred.user!;
    await _mergeLegacyDataToCurrentUid(user);
    final photo = _base64Image ?? '';

    // 2. Firestore Storage:
    // Keep UID as canonical owner key across providers.
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'username': name,
      'email': email,
      'photoBase64': photo,
      'photoUrl': user.photoURL ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'userId': user.uid,
    });

    // 3. Local Storage:
    // Persist UID as canonical identifier.
    await AuthSession.markSignedIn(user);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', name);
    await AppSession.markSetupComplete(userId: user.uid);

    // 4. Success Navigation
    if (mounted) {
      _showSnack('Account created! Welcome to Vox.', tone: _SnackTone.success);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      // Ensure the navigation matches your defined routes
      Navigator.of(context, rootNavigator: true).pushReplacementNamed('/home');
    }
  } on FirebaseAuthException {
    rethrow;
  } catch (e) {
    _showSnack('Error creating account: $e', tone: _SnackTone.error);
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}
  Future<void> _signInReturningUser(String password) async {
    if (_isLoading) return;
    if (mounted) setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = cred.user!;
      await _mergeLegacyDataToCurrentUid(user);

      await AuthSession.markSignedIn(user);
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final name = (doc.data()?['username'] as String?) ?? '';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userName', name);
      }
      await AppSession.markSetupComplete(userId: user.uid);

      if (mounted) {
        _showSnack('Welcome back!', tone: _SnackTone.success);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        Navigator.of(context, rootNavigator: true).pushReplacementNamed('/home');
      }
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e), tone: _SnackTone.error);
    } catch (e) {
      _showSnack('Sign-in error: $e', tone: _SnackTone.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !_isValidEmail(email)) {
      _showSnack('Enter a valid email first.', tone: _SnackTone.error);
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showSnack('Password reset email sent to $email.', tone: _SnackTone.success);
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e), tone: _SnackTone.error);
    } catch (e) {
      _showSnack('Error: $e', tone: _SnackTone.error);
    }
  }

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account with this email already exists. Try signing in.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect password. Try again or use Forgot Password.';
      case 'user-not-found':
        return 'No account found for this email. Please sign up.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection. Check your network and try again.';
      default:
        final msg = (e.message ?? '').trim();
        return msg.isNotEmpty ? msg : e.code;
    }
  }

  Future<void> _updateExistingProfile() async {
  if (mounted) setState(() => _isLoading = true);
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Updating Firestore with UID as canonical key.
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({
      'username': _nameController.text.trim(),
      'photoBase64': _base64Image ?? '',
      'userId': user.uid,
    });

    // Keep local prefs aligned with UID identity.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', _nameController.text.trim());
    await prefs.setString('userId', user.uid);

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

      await user.verifyBeforeUpdateEmail(newEmail);

      _showSnack(
          'Verification email sent to $newEmail. Verify to complete the switch.');
      if (mounted) {
        setState(() {
          _isSwitchingEmail = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      _showSnack('Failed to initiate email switch: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_googleLoading) return;
    if (mounted) setState(() => _googleLoading = true);
    
    AuthCredential? credential;
    final existingUser = FirebaseAuth.instance.currentUser;

    try {
      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        
        if (existingUser != null && existingUser.isAnonymous) {
          try {
            final result = await existingUser.linkWithPopup(googleProvider);
            await _syncGoogleUserDataAndRedirect(result.user);
            return;
          } on FirebaseAuthException catch (linkError) {
            if (linkError.code == 'credential-already-in-use' ||
                linkError.code == 'account-exists-with-different-credential') {
              credential = linkError.credential;
            } else {
              rethrow;
            }
          }
        } else {
          final result = await FirebaseAuth.instance.signInWithPopup(googleProvider);
          await _syncGoogleUserDataAndRedirect(result.user);
          return;
        }
      } else {
        final googleUser = await GoogleSignIn.instance.authenticate();
        final idToken = googleUser.authentication.idToken;
        if (idToken == null || idToken.isEmpty) {
          throw const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
            description:
                'Google did not return a sign-in token. Check Firebase SHA-1/SHA-256 and google-services.json.',
          );
        }
        credential = GoogleAuthProvider.credential(idToken: idToken);

        if (existingUser != null && existingUser.isAnonymous) {
          try {
            final result = await existingUser.linkWithCredential(credential);
            await _syncGoogleUserDataAndRedirect(result.user);
            return;
          } on FirebaseAuthException catch (linkError) {
            if (linkError.code == 'credential-already-in-use' ||
                linkError.code == 'account-exists-with-different-credential') {
              // Fall through to signInWithCredential below.
            } else {
              rethrow;
            }
          }
        }
      }

      if (credential != null) {
        // If already signed in with another provider (non-anonymous), try linking first.
        if (existingUser != null && !existingUser.isAnonymous) {
          try {
            final linked = await existingUser.linkWithCredential(credential);
            await _syncGoogleUserDataAndRedirect(linked.user);
            return;
          } on FirebaseAuthException catch (_) {
            // Fall back to sign-in flow below.
          }
        }
        final result = await FirebaseAuth.instance.signInWithCredential(credential);
        await _syncGoogleUserDataAndRedirect(result.user);
      }
    } catch (e) {
      final msg = _googleSignInUserMessage(e);
      if (msg.isNotEmpty) _showSnack(msg, tone: _SnackTone.error);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _syncGoogleUserDataAndRedirect(User? user) async {
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

    await AuthSession.markSignedIn(user);
    final prefs = await SharedPreferences.getInstance();
    if ((user.displayName ?? '').isNotEmpty) {
      await prefs.setString('userName', user.displayName!);
    }
    await _mergeLegacyDataToCurrentUid(user);
    await AppSession.markSetupComplete(userId: user.uid);

    if (!mounted) return;

    final dn = user.displayName?.trim();
    final em = user.email?.trim();
    final label =
        ((dn ?? '').isNotEmpty ? dn : null) ??
        ((em ?? '').isNotEmpty ? em : null);
    _showSnack(
      label != null
          ? 'Welcome back! Signed in as $label.'
          : 'Sign-in complete.',
      tone: _SnackTone.success,
      duration: const Duration(seconds: 3),
    );

    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushReplacementNamed('/home');
  }

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

  void _showSnack(
    String message, {
    _SnackTone tone = _SnackTone.neutral,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!mounted) return;
    final bg = switch (tone) {
      _SnackTone.success => VoxColors.primary(context),
      _SnackTone.error => VoxColors.danger,
      _SnackTone.neutral => VoxColors.surface(context),
    };
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        duration: duration,
      ),
    );
  }

  void _showGuestWarning() {
    final nav = Navigator.of(context, rootNavigator: true);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: VoxColors.bg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Heads up.",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: VoxColors.onBg(context),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Without an account, your activity won't be saved.",
              style: TextStyle(color: VoxColors.textSecondary(context)),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: VoxColors.onBg(context),
                      side: BorderSide(color: VoxColors.border(context)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      "Add Email",
                      style: TextStyle(color: VoxColors.onPrimary(context)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      try {
                        // Force a clean guest session so previous account data
                        // cannot leak into guest mode.
                        await FirebaseAuth.instance.signOut();
                        await AuthSession.markGuestContinue();
                        await FirebaseAuth.instance.signInAnonymously();
                        final guest = FirebaseAuth.instance.currentUser;
                        await AppSession.markSetupComplete(userId: guest?.uid);
                      } catch (e) {
                        debugPrint('Guest sign-in error: $e');
                      }
                      nav.pushReplacementNamed('/home');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VoxColors.primary(context),
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

  @override
  Widget build(BuildContext context) {
    if (_entryGatePending) {
      return VoxScaffoldWrapper(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: VoxColors.primary(context)),
              const SizedBox(height: 16),
              Text(
                'Checking this device…',
                style: TextStyle(color: VoxColors.textSecondary(context)),
              ),
            ],
          ),
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

          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: VoxColors.primary(context), width: 3),
                ),
                child: CircleAvatar(
                  radius: 52,
                  backgroundColor: VoxColors.primary(context).withValues(alpha: 0.1),
                  backgroundImage: _base64Image != null
                      ? _safeMemoryImage(_base64Image!)
                      : null,
                  child: _base64Image == null
                      ? Icon(Icons.camera_alt_outlined,
                          color: VoxColors.primary(context), size: 28)
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

          if (!_isEditingMode)
            _VoxTextField(
              controller: _passwordController,
              label: 'Password',
              icon: Icons.lock_outline,
              obscureText: !_passwordVisible,
              suffixIcon: IconButton(
                icon: Icon(
                  _passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: VoxColors.textHint(context),
                ),
                onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
              ),
            ),

          if (_canSwitchEmail && _isEditingMode && !_isSwitchingEmail)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton(
                onPressed: _requestEmailSwitch,
                child: Text(
                  'Switch Email',
                  style: TextStyle(color: VoxColors.primary(context)),
                ),
              ),
            ),

          const SizedBox(height: 32),

          _VoxButton(
            label: _isEditingMode ? 'SAVE PROFILE' : 'GET STARTED',
            isLoading: _isLoading,
            onTap: _onSaveTapped,
          ),

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
                style: TextStyle(color: VoxColors.textHint(context)),
              ),
            ),
          ),

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

// ─────────────────────────────────────────────────────────────
//  RETURNING USER VIEW (password sign-in)
// ─────────────────────────────────────────────────────────────
class _ReturningUserView extends StatefulWidget {
  final String email;
  final bool isLoading;
  final Future<void> Function(String password) onSignIn;
  final VoidCallback onForgotPassword;
  final VoidCallback onBack;

  const _ReturningUserView({
    super.key,
    required this.email,
    required this.isLoading,
    required this.onSignIn,
    required this.onForgotPassword,
    required this.onBack,
  });

  @override
  State<_ReturningUserView> createState() => _ReturningUserViewState();
}

class _ReturningUserViewState extends State<_ReturningUserView> {
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _VoxHeader(
          tag: 'WELCOME BACK',
          title: "YOU'RE\nALREADY HERE.",
          subtitle: "Sign in with your password to continue.",
        ),
        const SizedBox(height: 48),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: VoxColors.cardFill(context),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.email_outlined,
                        color: VoxColors.primary(context), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.email,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: VoxColors.onBg(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                TextField(
                  controller: _passwordController,
                  obscureText: !_passwordVisible,
                  style: TextStyle(color: VoxColors.onBg(context)),
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.lock_outline,
                        color: VoxColors.primary(context)),
                    labelText: 'Password',
                    labelStyle:
                        TextStyle(color: VoxColors.textHint(context)),
                    filled: true,
                    fillColor: VoxColors.surface(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          BorderSide(color: VoxColors.border(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                          color: VoxColors.primary(context), width: 1.5),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: VoxColors.textHint(context),
                      ),
                      onPressed: () => setState(
                          () => _passwordVisible = !_passwordVisible),
                    ),
                  ),
                  onSubmitted: (_) =>
                      widget.onSignIn(_passwordController.text),
                ),
                const SizedBox(height: 24),

                _VoxButton(
                  label: 'SIGN IN',
                  isLoading: widget.isLoading,
                  onTap: () => widget.onSignIn(_passwordController.text),
                ),
                const SizedBox(height: 12),

                Center(
                  child: TextButton(
                    onPressed: widget.onForgotPassword,
                    child: Text(
                      'Forgot Password?',
                      style:
                          TextStyle(color: VoxColors.primary(context)),
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                Center(
                  child: TextButton(
                    onPressed: widget.onBack,
                    child: Text(
                      'Use a different account',
                      style: TextStyle(
                          color: VoxColors.textHint(context)),
                    ),
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

// ─────────────────────────────────────────────────────────────
//  SHARED WIDGETS
// ─────────────────────────────────────────────────────────────
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
              color: VoxColors.primary(context).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              tag,
              style: TextStyle(
                color: VoxColors.primary(context),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              color: VoxColors.onBg(context),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: TextStyle(color: VoxColors.textSecondary(context)),
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
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;

  const _VoxTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: TextStyle(color: VoxColors.onBg(context)),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: VoxColors.primary(context)),
          labelText: label,
          labelStyle: TextStyle(color: VoxColors.textHint(context)),
          filled: true,
          fillColor: VoxColors.cardFill(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: VoxColors.border(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: VoxColors.primary(context), width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: VoxColors.border(context).withValues(alpha: 0.5)),
          ),
          suffixIcon: suffixIcon,
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
          backgroundColor: VoxColors.primary(context),
          disabledBackgroundColor: VoxColors.primary(context).withValues(alpha: 0.4),
          minimumSize: const Size(double.infinity, 56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: isLoading
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                    color: VoxColors.onPrimary(context), strokeWidth: 2),
              )
            : Text(
                label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: VoxColors.onPrimary(context),
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
          Expanded(child: Divider(color: VoxColors.border(context))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'OR',
              style: TextStyle(
                color: VoxColors.textHint(context),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Divider(color: VoxColors.border(context))),
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
          side: BorderSide(color: VoxColors.border(context)),
        ),
        child: isLoading
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                    color: VoxColors.primary(context), strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/Google_Logo.png', height: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Continue with Google',
                    style: TextStyle(
                      color: VoxColors.onBg(context),
                      fontWeight: FontWeight.w700,
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

  const VoxScaffoldWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VoxColors.bg(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: child,
        ),
      ),
    );
  }
}