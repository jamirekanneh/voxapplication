import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'language_provider.dart';
import 'profile_page.dart';
import 'contact_us_page.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  String _username = '';
  String? _base64Image;
  bool _isAnonymous = true;
  bool _loadingProfile = true;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _loadingProfile = true;
      _isOffline = false;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted)
        setState(() {
          _isAnonymous = true;
          _loadingProfile = false;
        });
      return;
    }
    if (mounted) setState(() => _isAnonymous = user.isAnonymous);

    if (!user.isAnonymous) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists && mounted) {
          final data = doc.data() ?? {};
          setState(() {
            _username = (data['username'] as String? ?? '').trim();
            final raw = data['photoBase64'] as String?;
            _base64Image = (raw != null && raw.isNotEmpty) ? raw : null;
          });
        }
      } on FirebaseException catch (e) {
        if (mounted) {
          setState(() => _isOffline = e.code == 'unavailable');
        }
        debugPrint('Profile load error: $e');
      } catch (e) {
        debugPrint('Profile load error: $e');
      }
    }
    if (mounted) setState(() => _loadingProfile = false);
  }

  Widget _buildAvatar({double radius = 34}) {
    if (_base64Image != null) {
      try {
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(base64Decode(_base64Image!)),
        );
      } catch (_) {
        // fall through to default
      }
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFBFA050),
      child: _isAnonymous
          ? Icon(Icons.person, size: radius, color: const Color(0xFFF3E5AB))
          : Text(
              _username.isNotEmpty ? _username[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: radius * 0.85,
                fontWeight: FontWeight.w900,
                color: const Color(0xFFF3E5AB),
              ),
            ),
    );
  }

  void _showLanguagePicker(BuildContext context, LanguageProvider lang) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF3E5AB),
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
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Text(
              lang.t('select_language'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                                  ? Colors.black
                                  : Colors.grey[300],
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  l,
                                  style: TextStyle(
                                    color: lang.selectedLanguage == l
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (lang.selectedLanguage == l)
                                  const Icon(
                                    Icons.check,
                                    color: Colors.white,
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

  void _handleLogout(BuildContext context, LanguageProvider lang) {
    showDialog(
      context: context,
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
                  "LOGOUT",
                  style: TextStyle(
                    color: Colors.white,
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
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                lang.t('logout_body'),
                style: const TextStyle(color: Colors.black54, fontSize: 14),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black,
                        side: const BorderSide(color: Colors.black26),
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
                        backgroundColor: Colors.red.shade700,
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
          color: isDanger ? Colors.red.shade700 : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDanger ? Colors.white : Colors.black87,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDanger ? Colors.white : Colors.black87,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style: const TextStyle(color: Colors.black45, fontSize: 12),
              )
            else
              Icon(
                isDanger ? Icons.logout : Icons.chevron_right,
                color: isDanger ? Colors.white70 : Colors.grey[400],
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
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.black38,
          letterSpacing: 2,
        ),
      ),
    );
  }

  void _openProfile(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePage(
          isAnonymous: _isAnonymous,
          username: _username,
          email: '',
          base64Image: _base64Image,
          photoUrl: null,
          onProfileUpdated: _loadProfile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      body: Column(
        children: [
          // ── Header ──────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              bottom: 24,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFD4B96A),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: Column(
              children: [
                const Text(
                  "VOX",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFF3E5AB),
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
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi_off,
                          color: Color(0xFFF3E5AB),
                          size: 13,
                        ),
                        SizedBox(width: 6),
                        Text(
                          "Offline — showing cached data",
                          style: TextStyle(
                            color: Color(0xFFF3E5AB),
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
                            color: Colors.white.withOpacity(0.2),
                          ),
                        )
                      : Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFF3E5AB),
                                  width: 2.5,
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
                                  color: Color(0xFFF3E5AB),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  color: Colors.black,
                                  size: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),

                // Username
                _loadingProfile
                    ? Container(
                        width: 100,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      )
                    : Text(
                        _isAnonymous
                            ? lang.t('guest')
                            : (_username.isNotEmpty ? _username : "Vox User"),
                        style: const TextStyle(
                          color: Color(0xFFF3E5AB),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                const SizedBox(height: 4),

                if (!_loadingProfile && _isAnonymous)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      lang.t('no_account'),
                      style: const TextStyle(
                        color: Color(0xFFF3E5AB),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Menu Items ───────────────────────────────
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
                    onTap: () {},
                  ),
                  _buildMenuItem(
                    icon: Icons.mic_none_rounded,
                    title: lang.t('menu_commands'),
                    onTap: () {},
                  ),
                  _buildMenuItem(
                    icon: Icons.info_outline_rounded,
                    title: lang.t('menu_about'),
                    onTap: () {},
                  ),

                  // ── Contact Us ── navigates to ContactUsPage ─────────────
                  _buildMenuItem(
                    icon: Icons.mail_outline_rounded,
                    title: lang.t('menu_contact'),
                    onTap: () => Navigator.push(
                      // ← UPDATED
                      context,
                      MaterialPageRoute(builder: (_) => const ContactUsPage()),
                    ),
                  ),

                  if (!_isAnonymous) ...[
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
        color: Colors.grey[850],
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
        backgroundColor: Colors.black,
        onPressed: () => Navigator.pushNamed(context, '/upload'),
        child: const Icon(Icons.file_upload_outlined, color: Colors.white),
      ),
    );
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
