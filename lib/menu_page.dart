import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'language_provider.dart';
import 'profile_page.dart';
import 'contact_us_page.dart';
import 'About_Us_Page.dart';

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
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AboutUsPage()),
                    ),
                  ),

                  // ── Contact Us ── navigates to ContactUsPage ─────────────
                  _buildMenuItem(
                    icon: Icons.mail_outline_rounded,
                    title: lang.t('menu_contact'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ContactUsPage()),
                    ),
                  ),

                  // ── Deleted Files (Recycle Bin) ──────────────────────────
                  _buildMenuItem(
                    icon: Icons.restore_from_trash_rounded,
                    title: 'Deleted Files',
                    onTap: () {
                      if (_isAnonymous) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Sign in to access deleted files.'),
                            backgroundColor: Color(0xFF333333),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DeletedFilesPage(),
                        ),
                      );
                    },
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

// ════════════════════════════════════════════════════════════
//  DELETED FILES PAGE  (Recycle Bin)
// ════════════════════════════════════════════════════════════

class DeletedFilesPage extends StatelessWidget {
  const DeletedFilesPage({super.key});

  CollectionReference get _bin {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('deleted_library');
  }

  Future<void> _restore(BuildContext context, DocumentSnapshot doc) async {
    try {
      final data = Map<String, dynamic>.from(
        doc.data() as Map<String, dynamic>,
      );
      data.remove('deletedAt');
      await FirebaseFirestore.instance.collection('library').add({
        ...data,
        'timestamp': FieldValue.serverTimestamp(),
      });
      await _bin.doc(doc.id).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${data['fileName']}" restored to library.'),
            backgroundColor: const Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Restore failed. Please try again.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _permanentDelete(
    BuildContext context,
    DocumentSnapshot doc,
  ) async {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['fileName'] as String? ?? 'File';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete permanently?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          '"$name" will be gone forever.',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.black54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _bin.doc(doc.id).delete();
    }
  }

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'epub':
        return Icons.menu_book;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _colorForType(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Colors.red.shade400;
      case 'doc':
      case 'docx':
        return Colors.blue.shade400;
      case 'ppt':
      case 'pptx':
        return Colors.orange.shade400;
      case 'xls':
      case 'xlsx':
        return Colors.green.shade400;
      case 'epub':
        return Colors.purple.shade400;
      default:
        return Colors.grey.shade500;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      appBar: AppBar(
        title: const Text(
          'Deleted Files',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: _bin.snapshots(),
            builder: (_, snap) {
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return const SizedBox.shrink();
              }
              return TextButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      title: const Text(
                        'Empty bin?',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      content: const Text(
                        'All deleted files will be permanently removed.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: const Text(
                            'Empty',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    for (final d in snap.data!.docs) {
                      await _bin.doc(d.id).delete();
                    }
                  }
                },
                icon: const Icon(
                  Icons.delete_sweep,
                  color: Colors.redAccent,
                  size: 18,
                ),
                label: const Text(
                  'Empty',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _bin.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.black),
            );
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 14),
                  Text(
                    'No deleted files',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Files you delete will appear here',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final name = data['fileName'] as String? ?? 'Unknown';
              final type = data['fileType'] as String? ?? 'file';
              final deletedAt = data['deletedAt'];
              String dateStr = '';
              if (deletedAt is Timestamp) {
                final dt = deletedAt.toDate();
                dateStr = '${dt.day}/${dt.month}/${dt.year}';
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _colorForType(type).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _iconForType(type),
                      color: _colorForType(type),
                      size: 24,
                    ),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: dateStr.isNotEmpty
                      ? Text(
                          'Deleted $dateStr',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 11,
                          ),
                        )
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Restore
                      Tooltip(
                        message: 'Restore to library',
                        child: IconButton(
                          icon: const Icon(
                            Icons.restore,
                            color: Color(0xFFD4B96A),
                            size: 24,
                          ),
                          onPressed: () => _restore(context, doc),
                        ),
                      ),
                      // Permanent delete
                      Tooltip(
                        message: 'Delete permanently',
                        child: IconButton(
                          icon: const Icon(
                            Icons.delete_forever,
                            color: Colors.redAccent,
                            size: 24,
                          ),
                          onPressed: () => _permanentDelete(context, doc),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
