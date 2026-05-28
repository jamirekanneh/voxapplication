import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart';
import 'services/app_session.dart';
import 'services/auth_session.dart';

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
  int _resendCooldownSeconds = 0;

  // Existing user email change tracking variables
  bool _isSwitchingEmail = false;
  bool _canSwitchEmail = false;

  // Spinning ring (kept for visual polish on loading states)
  late AnimationController _rotateController;

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
    _evaluateSwitchableEmail();
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

  void _evaluateSwitchableEmail() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous && (user.email?.isNotEmpty ?? false)) {
      setState(() => _canSwitchEmail = true);
    }
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
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final user = FirebaseAuth.instance.currentUser;

    if (name.isEmpty) {
      _showSnack("Name can't be empty");
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (user == null) throw Exception("No user authenticated.");

      // Handling Email Changes Explicitly
      if (_isSwitchingEmail) {
        if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
          _showSnack("Please enter a valid email address");
          setState(() => _isSaving = false);
          return;
        }
        await user.verifyBeforeUpdateEmail(email);
        _showSnack("Verification email sent to $email. Confirm to apply.");
      }

      // Handling Password Updates if Filled
      if (password.isNotEmpty) {
        if (password.length < 6) {
          _showSnack("Password must be at least 6 characters");
          setState(() => _isSaving = false);
          return;
        }
        await user.updatePassword(password);
      }

      // Update Firestore Record Specifications
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'username': name,
        if (!_isSwitchingEmail) 'email': email,
        'photoBase64': _base64Image ?? '',
        'userId': user.uid,
      });

      // Synchronize Local Session Metadata Cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', name);
      if (!_isSwitchingEmail) await prefs.setString('userEmail', email);

      widget.onProfileUpdated?.call();
      if (mounted) {
        setState(() {
          _isEditing = false;
          _isSwitchingEmail = false;
          _passwordController.clear();
        });
      }
      _showSnack("Profile updated");
    } catch (e) {
      String errorMessage = "Error saving: $e";
      if (e is FirebaseAuthException) {
        errorMessage = "Profile Error (${e.code}): ${e.message}";
      }
      _showSnack(errorMessage);
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
    if (confirm == true) {
      setState(() {
        _isSwitchingEmail = true;
        _emailController.clear();
      });
      _showSnack('Enter your new email address and tap Save to apply.');
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

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (!mounted) return;
    setState(() => _anonLoading = false);

    if (snapshot.docs.isNotEmpty) {
      // Email already registered — show password sign-in
      setState(() => _anonStage = 'returning');
    } else {
      await _createNewAccount(name, email, password);
    }
  }

  // —— Anonymous: create a brand new email/password account ——
  Future<void> _createNewAccount(String name, String email, String password) async {
    setState(() => _anonLoading = true);
    try {
      User? user = FirebaseAuth.instance.currentUser;
      UserCredential cred;

      if (user != null && user.isAnonymous) {
        // Upgrade anonymous account to email/password
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

      final newUser = cred.user!;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(newUser.uid)
          .set({
        'username': name,
        'email': email,
        'photoBase64': _base64Image ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'userId': newUser.uid,
      });

      final prefs = await SharedPreferences.getInstance();
      await AuthSession.markSignedIn(newUser);
      await prefs.setString('userName', name);
      await AppSession.markSetupComplete(userId: newUser.uid);

      widget.onProfileUpdated?.call();
      if (mounted) {
        _showSnack("Account created! Your data is now being saved.");
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e));
    } catch (e) {
      _showSnack("Error: $e");
    } finally {
      if (mounted) setState(() => _anonLoading = false);
    }
  }

  // —— Returning user: sign in with password ─────────
  Future<void> _signInReturningUser(String password) async {
    if (_anonLoading) return;
    setState(() => _anonLoading = true);
    final email = _emailController.text.trim();
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = cred.user!;

      final prefs = await SharedPreferences.getInstance();
      await AuthSession.markSignedIn(user);
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final name = (doc.data()?['username'] as String?) ?? '';
        await prefs.setString('userName', name);
      }
      await AppSession.markSetupComplete(userId: user.uid);

      widget.onProfileUpdated?.call();
      if (mounted) {
        _showSnack("Welcome back!");
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e));
    } catch (e) {
      _showSnack("Sign-in error: $e");
    } finally {
      if (mounted) setState(() => _anonLoading = false);
    }
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
        return 'No account found for this email.';
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
        widget.username.isNotEmpty ? widget.username[0].toUpperCase() : '?',
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
                        onTap: () => setState(() => _isEditing = true),
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
                              _isSwitchingEmail = false;
                              _nameController.text = widget.username;
                              _emailController.text = widget.email;
                              _passwordController.clear();
                              _base64Image = widget.base64Image;
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
                              value: widget.username.isNotEmpty ? widget.username : "Not set",
                              icon: Icons.person_outline_rounded,
                            ),
                      const SizedBox(height: 12),
                      
                      // Email Address
                      _isEditing
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _profileTextField(
                                  controller: _emailController,
                                  label: "Email Address",
                                  icon: Icons.alternate_email_rounded,
                                  enabled: _isSwitchingEmail,
                                ),
                                if (_canSwitchEmail && !_isSwitchingEmail)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4, top: 4),
                                    child: TextButton(
                                      onPressed: _requestEmailSwitch,
                                      child: Text(
                                        'Switch Email Address',
                                        style: TextStyle(
                                            color: VoxColors.primary(context),
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : _profileInfoTile(
                              label: "EMAIL",
                              value: widget.email.isNotEmpty ? widget.email : "Not set",
                              icon: Icons.alternate_email_rounded,
                              locked: true,
                            ),
                      const SizedBox(height: 12),

                      // Password field (Optional during editing setup)
                      if (_isEditing) ...[
                        _profileTextField(
                          controller: _passwordController,
                          label: "New Password (Optional)",
                          icon: Icons.lock_outline_rounded,
                          obscureText: !_passwordVisible,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: VoxColors.textHint(context),
                            ),
                            onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

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
                  onPressed: () => setState(() => _anonStage = 'join'),
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