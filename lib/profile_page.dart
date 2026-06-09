import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'language_provider.dart';
import 'theme_provider.dart';
import 'temp_library_provider.dart';
import 'temp_notes_provider.dart';
import 'navigation_keys.dart';
import 'services/app_session.dart';
import 'services/auth_session.dart';
import 'services/account_credentials_service.dart';
import 'services/email_change_service.dart';
import 'services/guest_upgrade_service.dart';
import 'services/mic_coordinator.dart';

const _kGoogleServerClientId =
    '1033671503358-c8dhmiu6henkq7ig0cg8ata4mq24a9af.apps.googleusercontent.com';

// ——————————————————————————————————————————————————
//  ProfilePage
// ——————————————————————————————————————————————————
class ProfilePage extends StatefulWidget {
  final bool isAnonymous;
  final String username;
  final String email;
  final String? base64Image;
  final String? photoUrl;
  final VoidCallback? onProfileUpdated;

  const ProfilePage({
    super.key,
    this.isAnonymous = true,
    this.username = '',
    this.email = '',
    this.base64Image,
    this.photoUrl,
    this.onProfileUpdated,
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
  late TextEditingController _passwordController;
  bool _passwordVisible = false;
  String? _base64Image;

  // Anonymous flow stages: 'join' | 'returning' | 'verify'
  String _anonStage = 'join';
  bool _anonLoading = false;
  bool _googleLoading = false;
  bool? _syncExistingCloudData;
  int _resendCooldownSeconds = 0;

  bool _credentialsBusy = false;

  // Snapshots taken when entering edit mode (for cancel).
  String? _editSnapshotName;
  String? _editSnapshotEmail;
  String? _editSnapshotImage;

  // Spinning ring (kept for visual polish on loading states)
  late AnimationController _rotateController;

  String get _displayName {
    final name = _nameController.text.trim();
    return name.isNotEmpty ? name : 'Not set';
  }

  String get _displayEmail {
    final email = _emailController.text.trim();
    return email.isNotEmpty ? email : 'Not set';
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.username);
    _emailController = TextEditingController(text: widget.email);
    _passwordController = TextEditingController();
    _base64Image = widget.base64Image;
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    if (widget.isAnonymous) {
      GoogleSignIn.instance.initialize(serverClientId: _kGoogleServerClientId);
    }
    _loadProfileFromFirestore();
  }

  Future<void> _loadProfileFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted) return;

      if (doc.exists) {
        final data = doc.data() ?? {};
        setState(() {
          _nameController.text =
              (data['username'] as String? ?? user.displayName ?? '').trim();
          _emailController.text =
              (data['email'] as String? ?? user.email ?? '').trim();
          final raw = data['photoBase64'] as String?;
          if (raw != null && raw.isNotEmpty) {
            _base64Image = raw;
          }
        });
      } else {
        setState(() {
          _nameController.text = user.displayName ?? _nameController.text;
          _emailController.text = user.email ?? _emailController.text;
        });
      }
    } catch (e) {
      debugPrint('Profile load error: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  // —— Pick image ——————————————————————————————————
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

  // —— Save edits (existing user) ——————————————————
  Future<void> _saveEdits() async {
    final name = _nameController.text.trim();
    final user = FirebaseAuth.instance.currentUser;

    if (name.isEmpty) {
      _showSnack("Name can't be empty");
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (user == null) throw Exception("No user authenticated.");

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'username': name,
        'email': user.email ?? _emailController.text.trim(),
        'photoBase64': _base64Image ?? '',
        'userId': user.uid,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', name);

      widget.onProfileUpdated?.call();
      if (mounted) {
        setState(() {
          _isEditing = false;
          _editSnapshotName = null;
          _editSnapshotEmail = null;
          _editSnapshotImage = null;
        });
      }
      _showSnack("Profile updated");
    } catch (e) {
      String errorMessage = "Error saving: $e";
      if (e is FirebaseAuthException) {
        errorMessage = AccountCredentialsService.authErrorMessage(e);
      }
      _showSnack(errorMessage);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // —— Anonymous: validate and proceed ──────────────
  Future<void> _onAnonSaveTapped() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || email.isEmpty) {
      _showSnack("Please fill in your name and email");
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      _showSnack("Please enter a valid email address");
      return;
    }
    if (password.length < 6) {
      _showSnack("Password must be at least 6 characters");
      return;
    }

    setState(() => _anonLoading = true);
    final exists = await GuestUpgradeService.emailExistsInSystem(email);
    if (!mounted) return;
    setState(() => _anonLoading = false);

    if (exists) {
      final sync = await _promptGuestDataSync(email: email);
      if (sync == null || !mounted) return;
      if (!sync) {
        final lang = context.read<LanguageProvider>();
        final confirmed = await _confirmDialog(
          title: lang.t('guest_save_fresh_confirm_title'),
          body: lang.t('guest_save_fresh_confirm_body'),
          confirmLabel: lang.t('profile_email_fresh_confirm_button'),
          destructive: true,
        );
        if (!confirmed || !mounted) return;
      }
      setState(() {
        _syncExistingCloudData = sync;
        _anonStage = 'returning';
      });
      return;
    }

    await _createNewAccount(name, email, password);
  }

  Future<bool?> _promptGuestDataSync({required String email}) async {
    final lang = context.read<LanguageProvider>();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Widget choiceCard({
          required String title,
          required String body,
          required IconData icon,
          required bool keep,
        }) {
          return Material(
            color: VoxColors.cardFill(ctx),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => Navigator.pop(ctx, keep),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: keep
                        ? VoxColors.primary(ctx).withValues(alpha: 0.4)
                        : VoxColors.danger.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          icon,
                          size: 20,
                          color:
                              keep ? VoxColors.primary(ctx) : VoxColors.danger,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: VoxColors.onSurface(ctx),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: VoxColors.textSecondary(ctx),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return AlertDialog(
          title: Text(lang.t('guest_save_sync_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  lang.tNamed('guest_save_sync_intro', {'email': email}),
                  style: TextStyle(
                    height: 1.45,
                    color: VoxColors.textSecondary(ctx),
                  ),
                ),
                const SizedBox(height: 16),
                choiceCard(
                  title: lang.t('guest_save_sync_keep_title'),
                  body: lang.t('guest_save_sync_keep_body'),
                  icon: Icons.cloud_done_outlined,
                  keep: true,
                ),
                const SizedBox(height: 10),
                choiceCard(
                  title: lang.t('guest_save_sync_fresh_title'),
                  body: lang.t('guest_save_sync_fresh_body'),
                  icon: Icons.delete_forever_outlined,
                  keep: false,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(lang.t('cancel')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _goHomeAfterUpgrade(String message) async {
    if (!mounted) return;
    _showSnack(message);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    MicCoordinator.instance.exitAuthFlow();
    globalNavigatorKey.currentState
        ?.pushNamedAndRemoveUntil('/home', (_) => false);
  }

  Future<void> _completeGuestUpgrade(
    User user, {
    required bool syncCloudData,
    required String name,
    String? email,
    required String successMessage,
  }) async {
    await GuestUpgradeService.applyCloudDataChoice(
      user: user,
      syncCloudData: syncCloudData,
      email: email ?? _emailController.text.trim(),
    );

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'username': name.isNotEmpty ? name : (user.displayName ?? ''),
      'email': user.email ?? email ?? '',
      'photoBase64': _base64Image ?? '',
      'photoUrl': user.photoURL ?? '',
      'userId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await AuthSession.markSignedIn(user);
    final prefs = await SharedPreferences.getInstance();
    final savedName = name.isNotEmpty ? name : (user.displayName ?? '');
    if (savedName.isNotEmpty) {
      await prefs.setString('userName', savedName);
    }

    if (!mounted) return;
    await GuestUpgradeService.uploadGuestSessionData(
      uid: user.uid,
      notes: context.read<TempNotesProvider>(),
      library: context.read<TempLibraryProvider>(),
    );

    await AppSession.markSetupComplete(userId: user.uid);
    widget.onProfileUpdated?.call();
    await _goHomeAfterUpgrade(successMessage);
  }

  // —— Anonymous: create a brand new email/password account ——
  Future<void> _createNewAccount(String name, String email, String password) async {
    final lang = context.read<LanguageProvider>();
    setState(() => _anonLoading = true);
    try {
      User? user = FirebaseAuth.instance.currentUser;
      UserCredential cred;

      if (user != null && user.isAnonymous) {
        final credential = EmailAuthProvider.credential(
          email: email,
          password: password,
        );
        cred = await user.linkWithCredential(credential);
      } else {
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      await _completeGuestUpgrade(
        cred.user!,
        syncCloudData: true,
        name: name,
        email: email,
        successMessage: lang.t('guest_save_success_new'),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        final sync = await _promptGuestDataSync(email: email);
        if (sync == null || !mounted) return;
        if (!sync) {
          final confirmed = await _confirmDialog(
            title: lang.t('guest_save_fresh_confirm_title'),
            body: lang.t('guest_save_fresh_confirm_body'),
            confirmLabel: lang.t('profile_email_fresh_confirm_button'),
            destructive: true,
          );
          if (!confirmed || !mounted) return;
        }
        setState(() {
          _syncExistingCloudData = sync;
          _anonStage = 'returning';
        });
      } else {
        _showSnack(_authErrorMessage(e));
      }
    } catch (e) {
      _showSnack("Error: $e");
    } finally {
      if (mounted) setState(() => _anonLoading = false);
    }
  }

  // —— Returning user: sign in with password ─────────
  Future<void> _signInReturningUser(String password) async {
    if (_anonLoading) return;
    final lang = context.read<LanguageProvider>();
    final sync = _syncExistingCloudData ?? true;
    setState(() => _anonLoading = true);
    final email = _emailController.text.trim();
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = cred.user!;
      final name = _nameController.text.trim();

      await _completeGuestUpgrade(
        user,
        syncCloudData: sync,
        name: name,
        email: email,
        successMessage: sync
            ? lang.t('guest_save_success_sync')
            : lang.t('guest_save_success_fresh'),
      );
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e));
    } catch (e) {
      _showSnack("Sign-in error: $e");
    } finally {
      if (mounted) setState(() => _anonLoading = false);
    }
  }

  Future<void> _handleGuestGoogleSignIn() async {
    if (_googleLoading || _anonLoading) return;
    final lang = context.read<LanguageProvider>();
    setState(() => _googleLoading = true);

    AuthCredential? credential;
    final existingUser = FirebaseAuth.instance.currentUser;

    try {
      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        if (existingUser != null && existingUser.isAnonymous) {
          try {
            final result = await existingUser.linkWithPopup(googleProvider);
            await _finishGuestGoogleSignIn(result.user, lang);
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
          final result =
              await FirebaseAuth.instance.signInWithPopup(googleProvider);
          await _finishGuestGoogleSignIn(result.user, lang);
          return;
        }
      } else {
        final googleUser = await GoogleSignIn.instance.authenticate();
        final idToken = googleUser.authentication.idToken;
        if (idToken == null || idToken.isEmpty) {
          throw const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
            description: 'Google did not return a sign-in token.',
          );
        }
        credential = GoogleAuthProvider.credential(idToken: idToken);

        if (existingUser != null && existingUser.isAnonymous) {
          try {
            final result = await existingUser.linkWithCredential(credential);
            await _finishGuestGoogleSignIn(result.user, lang);
            return;
          } on FirebaseAuthException catch (linkError) {
            if (linkError.code == 'credential-already-in-use' ||
                linkError.code == 'account-exists-with-different-credential') {
              // Fall through to signInWithCredential.
            } else {
              rethrow;
            }
          }
        }
      }

      if (credential != null) {
        final result =
            await FirebaseAuth.instance.signInWithCredential(credential);
        await _finishGuestGoogleSignIn(result.user, lang);
      }
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        _showSnack('Google sign-in cancelled or failed.');
      }
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e));
    } catch (e) {
      _showSnack('Google sign-in error: $e');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _finishGuestGoogleSignIn(
    User? user,
    LanguageProvider lang,
  ) async {
    if (user == null || !mounted) return;

    final hadProfile = await GuestUpgradeService.userHasCloudProfile(user.uid);
    var syncCloud = true;

    if (hadProfile) {
      if (_syncExistingCloudData != null) {
        syncCloud = _syncExistingCloudData!;
      } else {
        final email = user.email?.trim() ?? _emailController.text.trim();
        final choice = await _promptGuestDataSync(
          email: email.isNotEmpty ? email : 'your Google account',
        );
        if (choice == null || !mounted) return;
        syncCloud = choice;
        if (!syncCloud) {
          final confirmed = await _confirmDialog(
            title: lang.t('guest_save_fresh_confirm_title'),
            body: lang.t('guest_save_fresh_confirm_body'),
            confirmLabel: lang.t('profile_email_fresh_confirm_button'),
            destructive: true,
          );
          if (!confirmed || !mounted) return;
        }
      }
    }

    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : (user.displayName ?? '');

    await _completeGuestUpgrade(
      user,
      syncCloudData: syncCloud,
      name: name,
      email: user.email,
      successMessage: hadProfile
          ? (syncCloud
              ? lang.t('guest_save_success_sync')
              : lang.t('guest_save_success_fresh'))
          : lang.t('guest_save_success_new'),
    );
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showSnack('Enter a valid email first.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showSnack('Password reset email sent to $email.');
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e));
    } catch (e) {
      _showSnack('Error: $e');
    }
  }

  String _authErrorMessage(FirebaseAuthException e) =>
      AccountCredentialsService.authErrorMessage(e);

  Widget _flowBanner(
    BuildContext ctx, {
    required String message,
    IconData icon = Icons.info_outline_rounded,
    bool warning = false,
    bool danger = false,
  }) {
    final Color bg;
    final Color border;
    final Color iconColor;
    if (danger) {
      bg = VoxColors.danger.withValues(alpha: 0.1);
      border = VoxColors.danger.withValues(alpha: 0.35);
      iconColor = VoxColors.danger;
    } else if (warning) {
      bg = Colors.amber.withValues(alpha: 0.12);
      border = Colors.amber.withValues(alpha: 0.4);
      iconColor = Colors.amber.shade800;
    } else {
      bg = VoxColors.primary(ctx).withValues(alpha: 0.08);
      border = VoxColors.primary(ctx).withValues(alpha: 0.25);
      iconColor = VoxColors.primary(ctx);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: VoxColors.onSurface(ctx),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showOutcomeDialog({
    required String title,
    required String body,
    IconData icon = Icons.check_circle_outline_rounded,
    Color? iconColor,
  }) async {
    if (!mounted) return;
    final lang = context.read<LanguageProvider>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon, color: iconColor ?? VoxColors.primary(ctx), size: 32),
        title: Text(title, textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Text(body, style: const TextStyle(height: 1.5)),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(lang.t('profile_got_it')),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDialog({
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    if (!mounted) return false;
    final lang = context.read<LanguageProvider>();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(body, style: const TextStyle(height: 1.5)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.t('cancel')),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: VoxColors.danger)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _showChangeEmailSheet() async {
    final lang = context.read<LanguageProvider>();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    if (!AccountCredentialsService.hasPasswordProvider(user)) {
      await _showOutcomeDialog(
        title: context.read<LanguageProvider>().t('profile_change_email'),
        body: context.read<LanguageProvider>().t('profile_email_need_password_account'),
        icon: Icons.lock_outline_rounded,
        iconColor: Colors.amber.shade800,
      );
      return;
    }

    final currentEmailCtrl = TextEditingController(
      text: user.email?.trim() ?? _emailController.text.trim(),
    );
    final currentPasswordCtrl = TextEditingController();
    final newEmailCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    var step = 0;
    var obscureCurrent = true;
    var obscureNew = true;
    var verifying = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: !verifying,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: BoxDecoration(
                  color: VoxColors.surface(ctx),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: VoxColors.border(ctx)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      lang.t('profile_change_email'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: VoxColors.onSurface(ctx),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      step == 0
                          ? lang.t('profile_email_step_verify')
                          : lang.t('profile_email_step_new'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: VoxColors.primary(ctx),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _flowBanner(
                      ctx,
                      message: step == 0
                          ? lang.t('profile_email_verify_info')
                          : lang.t('profile_email_new_info'),
                      warning: step == 1,
                    ),
                    const SizedBox(height: 16),
                    if (step == 0) ...[
                      TextField(
                        controller: currentEmailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: lang.t('profile_current_email'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: currentPasswordCtrl,
                        obscureText: obscureCurrent,
                        decoration: InputDecoration(
                          labelText: lang.t('profile_current_password'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureCurrent
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () => setSheetState(
                              () => obscureCurrent = !obscureCurrent,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: newEmailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: lang.t('profile_new_email'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: newPasswordCtrl,
                        obscureText: obscureNew,
                        decoration: InputDecoration(
                          labelText: lang.t('profile_new_password'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureNew
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () =>
                                setSheetState(() => obscureNew = !obscureNew),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmPasswordCtrl,
                        obscureText: obscureNew,
                        decoration: InputDecoration(
                          labelText: lang.t('profile_confirm_password'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: verifying ? null : () => Navigator.pop(ctx),
                            child: Text(lang.t('cancel')),
                          ),
                        ),
                        Expanded(
                          child: FilledButton(
                            onPressed: verifying || _credentialsBusy
                                ? null
                                : () async {
                                    if (step == 0) {
                                      if (currentEmailCtrl.text.trim().isEmpty ||
                                          currentPasswordCtrl.text.isEmpty) {
                                        _showSnack(
                                          lang.t('profile_enter_current_password'),
                                        );
                                        return;
                                      }
                                      setSheetState(() => verifying = true);
                                      try {
                                        await EmailChangeService
                                            .verifyCurrentCredentials(
                                          email: currentEmailCtrl.text,
                                          password: currentPasswordCtrl.text,
                                        );
                                        if (!ctx.mounted) return;
                                        setSheetState(() {
                                          verifying = false;
                                          step = 1;
                                        });
                                      } on FirebaseAuthException catch (e) {
                                        if (!ctx.mounted) return;
                                        setSheetState(() => verifying = false);
                                        _showSnack(_authErrorMessage(e));
                                      } catch (e) {
                                        if (!ctx.mounted) return;
                                        setSheetState(() => verifying = false);
                                        _showSnack('Error: $e');
                                      }
                                      return;
                                    }

                                    final newEmail = newEmailCtrl.text.trim();
                                    final newPassword = newPasswordCtrl.text;
                                    if (newEmail.isEmpty ||
                                        !newEmail.contains('@')) {
                                      _showSnack('Enter a valid new email.');
                                      return;
                                    }
                                    if (newPassword.length < 6) {
                                      _showSnack(
                                        'New password must be at least 6 characters.',
                                      );
                                      return;
                                    }
                                    if (newPassword != confirmPasswordCtrl.text) {
                                      _showSnack(
                                        lang.t('profile_passwords_dont_match'),
                                      );
                                      return;
                                    }
                                    if (newEmail.toLowerCase() ==
                                        currentEmailCtrl.text
                                            .trim()
                                            .toLowerCase()) {
                                      _showSnack(
                                        'New email must differ from your current email.',
                                      );
                                      return;
                                    }

                                    Navigator.pop(ctx);
                                    await _promptEmailDataChoice(
                                      oldEmail: currentEmailCtrl.text.trim(),
                                      currentPassword: currentPasswordCtrl.text,
                                      newEmail: newEmail,
                                      newPassword: newPassword,
                                    );
                                  },
                            child: verifying
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: VoxColors.onPrimary(ctx),
                                    ),
                                  )
                                : Text(
                                    step == 0
                                        ? lang.t('profile_verify_continue')
                                        : lang.t('profile_change_email'),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    currentEmailCtrl.dispose();
    currentPasswordCtrl.dispose();
    newEmailCtrl.dispose();
    newPasswordCtrl.dispose();
    confirmPasswordCtrl.dispose();
  }

  Future<void> _promptEmailDataChoice({
    required String oldEmail,
    required String currentPassword,
    required String newEmail,
    required String newPassword,
  }) async {
    final lang = context.read<LanguageProvider>();
    final sync = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Widget choiceCard({
          required String title,
          required String body,
          required IconData icon,
          required bool keep,
        }) {
          return Material(
            color: VoxColors.cardFill(ctx),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => Navigator.pop(ctx, keep),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: keep
                        ? VoxColors.primary(ctx).withValues(alpha: 0.4)
                        : VoxColors.danger.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          icon,
                          size: 20,
                          color: keep ? VoxColors.primary(ctx) : VoxColors.danger,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: VoxColors.onSurface(ctx),
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: VoxColors.textHint(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: VoxColors.textSecondary(ctx),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return AlertDialog(
          title: Text(lang.t('profile_email_sync_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  lang.tNamed('profile_email_sync_intro', {'email': newEmail}),
                  style: TextStyle(
                    height: 1.45,
                    color: VoxColors.textSecondary(ctx),
                  ),
                ),
                const SizedBox(height: 16),
                choiceCard(
                  title: lang.t('profile_email_sync_keep_title'),
                  body: lang.t('profile_email_sync_keep_body'),
                  icon: Icons.cloud_done_outlined,
                  keep: true,
                ),
                const SizedBox(height: 10),
                choiceCard(
                  title: lang.t('profile_email_sync_fresh_title'),
                  body: lang.t('profile_email_sync_fresh_body'),
                  icon: Icons.delete_forever_outlined,
                  keep: false,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(lang.t('cancel')),
            ),
          ],
        );
      },
    );
    if (sync == null || !mounted) return;

    if (!sync) {
      final confirmed = await _confirmDialog(
        title: lang.t('profile_email_fresh_confirm_title'),
        body: lang.t('profile_email_fresh_confirm_body'),
        confirmLabel: lang.t('profile_email_fresh_confirm_button'),
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _credentialsBusy = true);
    try {
      await EmailChangeService.applyEmailChange(
        currentPassword: currentPassword,
        newEmail: newEmail,
        newPassword: newPassword,
        syncData: sync,
        oldEmail: oldEmail,
      );
      if (!mounted) return;
      setState(() {
        _emailController.text = newEmail;
      });
      widget.onProfileUpdated?.call();
      await _showOutcomeDialog(
        title: sync
            ? lang.t('profile_email_success_sync_title')
            : lang.t('profile_email_success_fresh_title'),
        body: lang.tNamed(
          sync
              ? 'profile_email_success_sync_body'
              : 'profile_email_success_fresh_body',
          {'email': newEmail},
        ),
        icon: sync ? Icons.mark_email_read_outlined : Icons.refresh_rounded,
      );
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e));
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _credentialsBusy = false);
    }
  }

  Future<void> _showChangePasswordSheet() async {
    final lang = context.read<LanguageProvider>();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    final emailCtrl = TextEditingController(
      text: user.email?.trim() ?? _emailController.text.trim(),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: VoxColors.surface(ctx),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: VoxColors.border(ctx)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  lang.t('profile_change_password'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: VoxColors.onSurface(ctx),
                  ),
                ),
                const SizedBox(height: 10),
                _flowBanner(ctx, message: lang.t('profile_password_reset_hint')),
                const SizedBox(height: 12),
                _flowBanner(
                  ctx,
                  message: lang.t('profile_password_steps'),
                  icon: Icons.format_list_numbered_rounded,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: lang.t('profile_current_email'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _credentialsBusy
                      ? null
                      : () async {
                          final email = emailCtrl.text.trim();
                          if (email.isEmpty || !email.contains('@')) {
                            _showSnack('Enter a valid email address.');
                            return;
                          }
                          Navigator.pop(ctx);
                          final confirmed = await _confirmDialog(
                            title: lang.t('profile_password_confirm_title'),
                            body: lang.tNamed(
                              'profile_password_confirm_body',
                              {'email': email},
                            ),
                            confirmLabel: lang.t('profile_send_reset_email'),
                          );
                          if (confirmed) {
                            await _sendPasswordResetEmail(email);
                          }
                        },
                  child: Text(lang.t('profile_send_reset_email')),
                ),
              ],
            ),
          ),
        );
      },
    );

    emailCtrl.dispose();
  }

  Future<void> _sendPasswordResetEmail(String email) async {
    final lang = context.read<LanguageProvider>();
    setState(() => _credentialsBusy = true);
    try {
      await AccountCredentialsService.sendPasswordResetEmail(email);
      if (!mounted) return;
      await _showOutcomeDialog(
        title: lang.t('profile_password_sent_title'),
        body: lang.tNamed('profile_password_sent_body', {'email': email}),
        icon: Icons.mark_email_read_outlined,
      );
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e));
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _credentialsBusy = false);
    }
  }

  Widget _buildSecuritySection() {
    final lang = context.watch<LanguageProvider>();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous || _isEditing) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            lang.t('profile_security_title').toUpperCase(),
            style: TextStyle(
              color: VoxColors.textSecondary(context),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ),
        _securityTile(
          icon: Icons.alternate_email_rounded,
          label: lang.t('profile_change_email'),
          subtitle: lang.t('profile_change_email_subtitle'),
          onTap: _credentialsBusy ? null : _showChangeEmailSheet,
        ),
        _securityTile(
          icon: Icons.lock_outline_rounded,
          label: lang.t('profile_change_password'),
          subtitle: lang.t('profile_change_password_subtitle'),
          onTap: _credentialsBusy ? null : _showChangePasswordSheet,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _securityTile({
    required IconData icon,
    required String label,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: VoxColors.surface(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: VoxColors.border(context)),
            ),
            child: Row(
              children: [
                Icon(icon, color: VoxColors.primary(context), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: VoxColors.onBg(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: VoxColors.textHint(context),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: VoxColors.textHint(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: VoxColors.surface(context),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ——————————————————————————————————————————————————
  //  AVATAR WIDGET
  // ——————————————————————————————————————————————————
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
      backgroundColor: VoxColors.primary(context),
      child: Text(
        _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()[0].toUpperCase()
            : '?',
        style: TextStyle(
          fontSize: radius * 0.85,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }

  // ——————————————————————————————————————————————————
  //  BUILD
  // ——————————————————————————————————————————————————
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VoxColors.bg(context),
      body: widget.isAnonymous ? _buildAnonView() : _buildProfileView(),
    );
  }

  // ——————————————————————————————————————————————————
  //  EXISTING USER PROFILE VIEW
  // ——————————————————————————————————————————————————
  Widget _buildProfileView() {
    return Stack(
      children: [
        Positioned(
          top: -60,
          right: -60,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: VoxColors.primary(context).withValues(alpha: 0.04),
            ),
          ),
        ),
        Positioned(
          bottom: -80,
          left: -60,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: VoxColors.primary(context).withValues(alpha: 0.03),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: VoxColors.surface(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: VoxColors.border(context)),
                        ),
                        child: Icon(Icons.arrow_back_ios_new,
                            color: VoxColors.onBg(context), size: 16),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        "PROFILE",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                          color: VoxColors.onBg(context),
                        ),
                      ),
                    ),
                    if (!_isEditing)
                      GestureDetector(
                        onTap: () => setState(() {
                          _editSnapshotName = _nameController.text;
                          _editSnapshotEmail = _emailController.text;
                          _editSnapshotImage = _base64Image;
                          _isEditing = true;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: VoxColors.surface(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: VoxColors.border(context)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.edit, color: VoxColors.onBg(context), size: 14),
                              const SizedBox(width: 6),
                              Text(
                                "EDIT",
                                style: TextStyle(
                                  color: VoxColors.onBg(context),
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
                              _nameController.text =
                                  _editSnapshotName ?? _nameController.text;
                              _emailController.text =
                                  _editSnapshotEmail ?? _emailController.text;
                              _base64Image = _editSnapshotImage;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: VoxColors.border(context),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "CANCEL",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  color: VoxColors.textSecondary(context),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _isSaving ? null : _saveEdits,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: VoxColors.primary(context),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: _isSaving
                                  ? SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          color: VoxColors.onPrimary(context),
                                          strokeWidth: 2),
                                    )
                                  : Text(
                                      "SAVE",
                                      style: TextStyle(
                                        color: VoxColors.onPrimary(context),
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
                      GestureDetector(
                        onTap: _isEditing ? _pickImage : null,
                        child: Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: VoxColors.primary(context),
                                    width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: VoxColors.primary(context).withValues(alpha: 0.25),
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
                                  decoration: BoxDecoration(
                                    color: VoxColors.bg(context),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.camera_alt,
                                      color: VoxColors.onBg(context), size: 14),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // Full Name
                      _isEditing
                          ? _profileTextField(
                              controller: _nameController,
                              label: "Full Name",
                              icon: Icons.person_outline_rounded,
                            )
                          : _profileInfoTile(
                              label: "NAME",
                              value: _displayName,
                              icon: Icons.person_outline_rounded,
                            ),
                      const SizedBox(height: 12),
                      
                      // Email (read-only — use Account security to change)
                      _isEditing
                          ? _profileInfoTile(
                              label: "EMAIL",
                              value: _emailController.text.isNotEmpty
                                  ? _emailController.text
                                  : "Not set",
                              icon: Icons.alternate_email_rounded,
                              locked: true,
                            )
                          : _profileInfoTile(
                              label: "EMAIL",
                              value: _displayEmail,
                              icon: Icons.alternate_email_rounded,
                              locked: true,
                            ),
                      const SizedBox(height: 12),

                      if (!_isEditing) _buildSecuritySection(),

                      if (_isEditing) const SizedBox(height: 0) else const SizedBox(height: 4),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: VoxColors.surface(context),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: VoxColors.border(context)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: VoxColors.primary(context).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.verified_outlined,
                                color: VoxColors.primary(context),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "ACCOUNT STATUS",
                                  style: TextStyle(
                                    color: VoxColors.textSecondary(context),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  "Active — data is being saved",
                                  style: TextStyle(
                                    color: VoxColors.onBg(context),
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
        color: VoxColors.cardFill(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VoxColors.border(context), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: VoxColors.primary(context).withValues(alpha: 0.7)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: VoxColors.textHint(context),
                    )),
                const SizedBox(height: 3),
                Text(value,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: VoxColors.onBg(context),
                    )),
              ],
            ),
          ),
          if (locked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: VoxColors.onBg(context).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "LOCKED",
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: VoxColors.textHint(context)),
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
    bool enabled = true,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: VoxColors.onBg(context)),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: VoxColors.primary(context).withValues(alpha: 0.7), size: 20),
          labelText: label,
          labelStyle: TextStyle(color: VoxColors.textHint(context), fontSize: 14, fontWeight: FontWeight.w500),
          filled: true,
          fillColor: VoxColors.cardFill(context),
          suffixIcon: suffixIcon,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: VoxColors.border(context), width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: VoxColors.primary(context), width: 2),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: VoxColors.border(context).withValues(alpha: 0.4), width: 1.5),
          ),
        ),
      ),
    );
  }

  // ——————————————————————————————————————————————————
  //  ANONYMOUS VIEW
  // ——————————————————————————————————————————————————
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
              color: VoxColors.primary(context).withValues(alpha: 0.04),
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
              color: VoxColors.primary(context).withValues(alpha: 0.03),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: VoxColors.surface(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: VoxColors.border(context)),
                        ),
                        child: Icon(Icons.arrow_back_ios_new,
                            color: VoxColors.onBg(context), size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
                    child: child,
                  ),
                  child: switch (_anonStage) {
                    'join' => _anonJoinView(),
                    'returning' => _anonReturningView(),
                    'verify' => _anonVerifyView(),
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
            subtitle: "Add your details and your Vox data will be saved from this point forward.",
          ),
          const SizedBox(height: 36),
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: VoxColors.primary(context), width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: VoxColors.primary(context).withValues(alpha: 0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 52,
                      backgroundColor: VoxColors.primary(context).withValues(alpha: 0.08),
                      backgroundImage: _base64Image != null ? MemoryImage(base64Decode(_base64Image!)) : null,
                      child: _base64Image == null
                          ? Icon(Icons.camera_alt_outlined,
                              color: VoxColors.primary(context).withValues(alpha: 0.5), size: 28)
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: VoxColors.primary(context), shape: BoxShape.circle),
                      child: Icon(Icons.edit, color: VoxColors.bg(context), size: 13),
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
          _anonPasswordField(),
          const SizedBox(height: 8),
          _anonButton(
            label: "SAVE & START",
            isLoading: _anonLoading,
            onTap: _onAnonSaveTapped,
          ),
          const SizedBox(height: 20),
          _anonDivider(),
          const SizedBox(height: 16),
          _anonGoogleButton(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // Stage 2 — Returning user (password sign-in)
  Widget _anonReturningView() {
    final passwordCtrl = TextEditingController();
    bool pwVisible = false;

    return StatefulBuilder(
      key: const ValueKey('returning'),
      builder: (context, setSubState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _anonHeader(
                tag: "WELCOME BACK",
                title: "YOU'RE\nALREADY HERE.",
                subtitle: "This email is registered. Type your password to sync your local logs.",
              ),
              const SizedBox(height: 36),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: VoxColors.cardFill(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: VoxColors.border(context)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.alternate_email_rounded, color: VoxColors.primary(context), size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _emailController.text,
                        style: TextStyle(
                          color: VoxColors.onBg(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: !pwVisible,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: VoxColors.onBg(context)),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline_rounded,
                      color: VoxColors.primary(context).withValues(alpha: 0.7), size: 20),
                  labelText: "Password",
                  labelStyle: TextStyle(
                      color: VoxColors.textHint(context), fontSize: 14, fontWeight: FontWeight.w500),
                  filled: true,
                  fillColor: VoxColors.cardFill(context),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: VoxColors.border(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: VoxColors.primary(context), width: 2),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(pwVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: VoxColors.textHint(context), size: 20),
                    onPressed: () => setSubState(() => pwVisible = !pwVisible),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _anonButton(
                label: "SYNC ACCOUNT",
                isLoading: _anonLoading,
                onTap: () => _signInReturningUser(passwordCtrl.text),
              ),
              const SizedBox(height: 20),
              _anonDivider(),
              const SizedBox(height: 16),
              _anonGoogleButton(),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _sendPasswordReset,
                  child: Text(
                    "Forgot Password?",
                    style: TextStyle(
                        color: VoxColors.primary(context), fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    _anonStage = 'join';
                    _syncExistingCloudData = null;
                  }),
                  child: Text(
                    "Use a different email",
                    style: TextStyle(
                        color: VoxColors.textSecondary(context), fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Stage 3 — Email verification workflow panel placeholder
  Widget _anonVerifyView() {
    return SingleChildScrollView(
      key: const ValueKey('verify'),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _anonHeader(
            tag: "VERIFICATION SENT",
            title: "CHECK YOUR\nINBOX.",
            subtitle: "We sent a link to ${_emailController.text}. Open it to finalize setup.",
          ),
          const SizedBox(height: 48),
          Center(
            child: AnimatedBuilder(
              animation: _rotateController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _rotateController.value * 2.0 * pi,
                  child: child,
                );
              },
              child: CustomPaint(
                size: const Size(80, 80),
                painter: _SweepRingPainter(VoxColors.primary(context)),
              ),
            ),
          ),
          const SizedBox(height: 48),
          _anonButton(
            label: "I CONFIRMED THE LINK",
            onTap: () async {
              setState(() => _anonLoading = true);
              await FirebaseAuth.instance.currentUser?.reload();
              final isVerified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;
              setState(() => _anonLoading = false);

              if (isVerified) {
                _showSnack("Verified! Opening logs...");
                widget.onProfileUpdated?.call();
                if (mounted) Navigator.pop(context);
              } else {
                _showSnack("Email not verified yet. Check spam folder.");
              }
            },
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: _resendCooldownSeconds > 0
                  ? null
                  : () async {
                      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
                      _showSnack("Verification resent.");
                      setState(() => _resendCooldownSeconds = 60);
                      Timer.periodic(const Duration(seconds: 1), (timer) {
                        if (!mounted) {
                          timer.cancel();
                          return;
                        }
                        setState(() {
                          if (_resendCooldownSeconds > 0) {
                            _resendCooldownSeconds--;
                          } else {
                            timer.cancel();
                          }
                        });
                      });
                    },
              child: Text(
                _resendCooldownSeconds > 0 ? "Resend in ${_resendCooldownSeconds}s" : "Resend Link",
                style: TextStyle(
                  color: _resendCooldownSeconds > 0 ? VoxColors.textHint(context) : VoxColors.primary(context),
                  fontWeight: FontWeight.w600,
                  decoration: _resendCooldownSeconds > 0 ? TextDecoration.none : TextDecoration.underline,
                  decorationColor: VoxColors.primary(context),
                ),
              ),
            ),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('hasProfile', true);
                  if (mounted) Navigator.pop(context);
                },
                child: const Text("⚠️ Skip (debug only)",
                    style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _anonDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: VoxColors.border(context))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR',
            style: TextStyle(
              color: VoxColors.textHint(context),
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(child: Divider(color: VoxColors.border(context))),
      ],
    );
  }

  Widget _anonGoogleButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: (_googleLoading || _anonLoading)
            ? null
            : _handleGuestGoogleSignIn,
        icon: _googleLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: VoxColors.primary(context),
                ),
              )
            : const Icon(Icons.g_mobiledata_rounded, size: 28),
        label: const Text(
          'Continue with Google',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: VoxColors.border(context)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // —— Shared anon widgets ————————————————————————
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
            color: VoxColors.primary(context).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: VoxColors.primary(context).withValues(alpha: 0.3)),
          ),
          child: Text(tag,
              style: TextStyle(
                  color: VoxColors.primary(context),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2)),
        ),
        const SizedBox(height: 12),
        Text(title,
            style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w900,
                height: 1.05,
                letterSpacing: -1.5,
                color: VoxColors.onBg(context))),
        const SizedBox(height: 10),
        Text(subtitle,
            style: TextStyle(
                color: VoxColors.textSecondary(context),
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
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: VoxColors.onBg(context)),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: VoxColors.primary(context).withValues(alpha: 0.7), size: 20),
          labelText: label,
          labelStyle: TextStyle(color: VoxColors.textHint(context), fontSize: 14, fontWeight: FontWeight.w500),
          filled: true,
          fillColor: VoxColors.cardFill(context),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: VoxColors.border(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: VoxColors.primary(context), width: 2),
          ),
        ),
      ),
    );
  }

  Widget _anonPasswordField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: TextField(
        controller: _passwordController,
        obscureText: !_passwordVisible,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: VoxColors.onBg(context)),
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.lock_outline_rounded,
              color: VoxColors.primary(context).withValues(alpha: 0.7), size: 20),
          labelText: "Password",
          labelStyle: TextStyle(color: VoxColors.textHint(context), fontSize: 14, fontWeight: FontWeight.w500),
          filled: true,
          fillColor: VoxColors.cardFill(context),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: VoxColors.border(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: VoxColors.primary(context), width: 2),
          ),
          suffixIcon: IconButton(
            icon: Icon(_passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: VoxColors.textHint(context), size: 20),
            onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
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
          backgroundColor: VoxColors.primary(context),
          foregroundColor: Colors.white,
          disabledBackgroundColor: VoxColors.primary(context).withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 14)),
      ),
    );
  }
}

// —— Sweep ring painter ————————————————————————
class _SweepRingPainter extends CustomPainter {
  final Color primaryColor;
  _SweepRingPainter(this.primaryColor);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: Offset(size.width / 2, size.height / 2), radius: size.width / 2 - 4);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = SweepGradient(
        colors: [
          primaryColor.withValues(alpha: 0),
          primaryColor,
        ],
      ).createShader(rect);
    canvas.drawArc(rect, 0, pi * 1.8, false, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}