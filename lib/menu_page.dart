import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'language_provider.dart';
import 'profile_page.dart';
import 'contact_us_page.dart';
import 'about_us_page.dart';
import 'recycle_bin_page.dart';
import 'custom_commands_page.dart';
import 'statistics_page.dart';
import 'ask_questions_page.dart';
import 'saved_assessments_page.dart';
import 'analytics_service.dart';
import 'floating_chat_bot.dart';
import 'recommendations_page.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  String _username = '';
  String _email = '';
  String? _base64Image;
  String? _photoUrl;

  // A user is treated as "registered" if they have a Firestore profile doc.
  // This can be true even for anonymous Firebase Auth users who filled in
  // the profile form (our new-user flow saves under anonymous UID).
  bool _hasProfile = false;
  bool _isFirebaseAnonymous = true;
  bool _loadingProfile = true;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    AnalyticsService.instance.startFeatureSession('Menu');
  }

  @override
  void dispose() {
    AnalyticsService.instance.endFeatureSession('Menu');
    super.dispose();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  LOAD PROFILE
  //  Priority:
  //  1. Firebase Auth user â†’ look up Firestore by UID
  //  2. If anonymous Auth user â†’ try Firestore by email from SharedPrefs
  //  3. If no match â†’ treat as guest
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _loadingProfile = true;
      _isOffline = false;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('userEmail') ?? '';
      final hasProfilePref = prefs.getBool('hasProfile') ?? false;

      // â”€â”€ No auth user at all â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      if (user == null) {
        if (mounted) {
          setState(() {
            _hasProfile = false;
            _isFirebaseAnonymous = true;
            _loadingProfile = false;
          });
        }
        return;
      }

      _isFirebaseAnonymous = user.isAnonymous;

      // â”€â”€ Real (non-anonymous) Firebase Auth user â”€â”€
      if (!user.isAnonymous) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists && mounted) {
          final data = doc.data()!;
          setState(() {
            _username = (data['username'] as String? ?? '').trim();
            _email = data['email'] as String? ?? '';
            final raw = data['photoBase64'] as String?;
            _base64Image = (raw != null && raw.isNotEmpty) ? raw : null;
            _photoUrl = data['photoUrl'] as String?;
            _hasProfile = true;
          });
        }
        if (mounted) setState(() => _loadingProfile = false);
        return;
      }

      // â”€â”€ Anonymous Firebase Auth user â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // Check if they filled in the profile form (saved under anonymous UID)
      if (hasProfilePref) {
        // First try by UID (new user who just signed up)
        final uidDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (uidDoc.exists && mounted) {
          final data = uidDoc.data()!;
          setState(() {
            _username = (data['username'] as String? ?? '').trim();
            _email = data['email'] as String? ?? savedEmail;
            final raw = data['photoBase64'] as String?;
            _base64Image = (raw != null && raw.isNotEmpty) ? raw : null;
            _photoUrl = data['photoUrl'] as String?;
            _hasProfile = true;
          });
          if (mounted) setState(() => _loadingProfile = false);
          return;
        }

        // Fallback: look up by email from SharedPrefs
        if (savedEmail.isNotEmpty) {
          final emailQuery = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: savedEmail)
              .limit(1)
              .get();

          if (emailQuery.docs.isNotEmpty && mounted) {
            final data = emailQuery.docs.first.data();
            setState(() {
              _username = (data['username'] as String? ?? '').trim();
              _email = data['email'] as String? ?? savedEmail;
              final raw = data['photoBase64'] as String?;
              _base64Image = (raw != null && raw.isNotEmpty) ? raw : null;
              _photoUrl = data['photoUrl'] as String?;
              _hasProfile = true;
            });
            if (mounted) setState(() => _loadingProfile = false);
            return;
          }
        }

        // hasProfile pref was set but no Firestore doc found â€” use saved name
        final savedName = prefs.getString('userName') ?? '';
        if (savedName.isNotEmpty && mounted) {
          setState(() {
            _username = savedName;
            _email = savedEmail;
            _hasProfile = true;
          });
        }
      }

      // Pure guest â€” no profile
      if (mounted) {
        setState(() {
          _hasProfile = false;
          _loadingProfile = false;
        });
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _isOffline = e.code == 'unavailable';
          _loadingProfile = false;
        });
      }
      debugPrint('Profile load error: $e');
    } catch (e) {
      if (mounted) setState(() => _loadingProfile = false);
      debugPrint('Profile load error: $e');
    }

    if (mounted) setState(() => _loadingProfile = false);
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  AVATAR
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildAvatar({double radius = 34}) {
    // Photo from base64
    if (_base64Image != null) {
      try {
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(base64Decode(_base64Image!)),
        );
      } catch (_) {}
    }
    // Google profile photo
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(_photoUrl!),
      );
    }
    // Initials / guest icon
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFBFA050),
      child: !_hasProfile
          ? Icon(Icons.person, size: radius, color: const Color(0xFFF0F4FF))
          : Text(
              _username.isNotEmpty ? _username[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: radius * 0.85,
                fontWeight: FontWeight.w900,
                color: const Color(0xFFF0F4FF),
              ),
            ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  LANGUAGE PICKER
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _showLanguagePicker(BuildContext context, LanguageProvider lang) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141A29),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Text(
              lang.t('select_language'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: lang.languages
                      .map(
                        (l) => GestureDetector(
                          onTap: () {
                            lang.setLanguage(l);
                            Navigator.pop(context);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: lang.selectedLanguage == l
                                  ? const Color(0xFF4B9EFF)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: lang.selectedLanguage == l
                                    ? const Color(0xFF4B9EFF)
                                    : Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  l,
                                  style: TextStyle(
                                    color: lang.selectedLanguage == l
                                        ? const Color(0xFF0A0E1A)
                                        : Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (lang.selectedLanguage == l)
                                  const Icon(
                                    Icons.check_circle,
                                    color: Color(0xFF0A0E1A),
                                    size: 18,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  LOGOUT
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _handleLogout(BuildContext context, LanguageProvider lang) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF141A29),
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
                  color: const Color(0xFFFF5252).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.2)),
                ),
                child: const Text(
                  "LOGOUT",
                  style: TextStyle(
                    color: Color(0xFFFF5252),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                lang.t('logout_title'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                lang.t('logout_body'),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        lang.t('logout_cancel'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(context, '/');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5252),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: Text(
                        lang.t('logout_confirm'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
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
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  OPEN PROFILE PAGE
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _openProfile(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePage(
          isAnonymous: !_hasProfile,
          username: _username,
          email: _email,
          base64Image: _base64Image,
          photoUrl: _photoUrl,
          onProfileUpdated: _loadProfile,
        ),
      ),
    );
    // Reload after returning in case profile was updated
    _loadProfile();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  HELPERS
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    String? trailing,
    VoidCallback? onTap,
    bool isDanger = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDanger ? const Color(0xFFFF5252).withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDanger ? const Color(0xFFFF5252).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDanger ? const Color(0xFFFF5252) : const Color(0xFF4B9EFF),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDanger ? const Color(0xFFFF5252) : Colors.white,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              )
            else
              Icon(
                isDanger ? Icons.logout : Icons.chevron_right,
                color: isDanger ? const Color(0xFFFF5252).withValues(alpha: 0.5) : Colors.white24,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 12),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: 0.3),
          letterSpacing: 2,
        ),
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  BUILD
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();

    return FloatingBotWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        body: Column(
        children: [
          // â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              bottom: 24,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF0A0E1A),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Column(
              children: [
                const Text(
                  "VOX",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF4B9EFF),
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 18),

                // Offline banner
                if (_isOffline)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Color(0xFF0A0E1A).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi_off,
                          color: Color(0xFFF0F4FF),
                          size: 13,
                        ),
                        SizedBox(width: 6),
                        Text(
                          "Offline â€” showing cached data",
                          style: TextStyle(
                            color: Color(0xFFF0F4FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Avatar
                GestureDetector(
                  onTap: () => _openProfile(context),
                  child: _loadingProfile
                      ? Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        )
                      : Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF4B9EFF),
                                  width: 2.0,
                                ),
                              ),
                              child: _buildAvatar(radius: 34),
                            ),
                            Positioned(
                              bottom: 2,
                              right: 2,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF4B9EFF),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  color: Color(0xFF0A0E1A),
                                  size: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),

                // Username or loading shimmer
                _loadingProfile
                    ? Container(
                        width: 100,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      )
                    : Text(
                        // Show name if profile exists, otherwise "Guest"
                        _hasProfile
                            ? (_username.isNotEmpty ? _username : "Vox User")
                            : lang.t('guest'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                // Email subtitle (only when profile exists)
                if (!_loadingProfile && _hasProfile && _email.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _email,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                const SizedBox(height: 4),

                // "No account" badge for pure guests
                if (!_loadingProfile && !_hasProfile)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Color(0xFF0A0E1A).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      lang.t('no_account'),
                      style: const TextStyle(
                        color: Color(0xFF4B9EFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // â”€â”€ Menu Items â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel(lang.t('section_account')),
                  _buildMenuItem(
                    icon: Icons.person_outline_rounded,
                    title: lang.t('menu_profile'),
                    onTap: () => _openProfile(context),
                  ),
                  _buildMenuItem(
                    icon: Icons.language_rounded,
                    title: lang.t('menu_language'),
                    trailing: lang.selectedLanguage,
                    onTap: () => _showLanguagePicker(context, lang),
                  ),
                  _sectionLabel(lang.t('section_app')),
                  _buildMenuItem(
                    icon: Icons.bar_chart_outlined,
                    title: lang.t('menu_statistics'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StatisticsPage()),
                    ),
                  ),
                  if (_hasProfile) ...[
                    _buildMenuItem(
                      icon: Icons.bookmarks_outlined,
                      title: 'Saved Q&A',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SavedAssessmentsPage(),
                        ),
                      ),
                    ),
                    _buildMenuItem(
                      icon: Icons.lightbulb_outline_rounded,
                      title: 'Recommendations',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RecommendationsPage(),
                        ),
                      ),
                    ),
                  ],
                  _buildMenuItem(
                    icon: Icons.mic_none_rounded,
                    title: 'Personalized Commands',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CustomCommandsPage(),
                        ),
                      );
                    },
                  ),
                  _buildMenuItem(
                    icon: Icons.info_outline_rounded,
                    title: lang.t('menu_about'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AboutUsPage()),
                    ),
                  ),
                  _buildMenuItem(
                    icon: Icons.question_answer_outlined,
                    title: 'FAQs',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AskQuestionsPage(),
                      ),
                    ),
                  ),
                  _buildMenuItem(
                    icon: Icons.mail_outline_rounded,
                    title: lang.t('menu_contact'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ContactUsPage()),
                    ),
                  ),
                  if (_hasProfile) ...[
                    _buildMenuItem(
                      icon: Icons.delete_sweep_rounded,
                      title: 'Recycle Bin',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const RecycleBinPage(),
                        ),
                      ),
                    ),
                  ],

                  // Logout â€” show for any user that has a verified account
                  if (_hasProfile || !_isFirebaseAnonymous) ...[
                    const SizedBox(height: 4),
                    _buildMenuItem(
                      icon: Icons.logout_rounded,
                      title: lang.t('menu_logout'),
                      isDanger: true,
                      onTap: () => _handleLogout(context, lang),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: BottomAppBar(
        color: Color(0xFF141A29),
        shape: const CircularNotchedRectangle(),
        child: SizedBox(
          height: 65,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(
                Icons.home,
                lang.t('nav_home'),
                Colors.grey[400]!,
                onTap: () => Navigator.pushReplacementNamed(context, '/home'),
              ),
              _navItem(
                Icons.note_alt_outlined,
                lang.t('nav_notes'),
                Colors.grey[400]!,
                onTap: () => Navigator.pushReplacementNamed(context, '/notes'),
              ),
              const SizedBox(width: 48),
              _navItem(
                Icons.book,
                lang.t('nav_dictionary'),
                Colors.grey[400]!,
                onTap: () =>
                    Navigator.pushReplacementNamed(context, '/dictionary'),
              ),
              _navItem(Icons.menu, lang.t('nav_menu'), Colors.white),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Color(0xFF0A0E1A),
        onPressed: () => Navigator.pushNamed(context, '/upload'),
        child: const Icon(Icons.file_upload_outlined, color: Colors.white),
      ),
    ));
  }

  Widget _navItem(
    IconData icon,
    String label,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

