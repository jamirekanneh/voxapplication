import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'language_provider.dart';
import 'tts_service.dart';
import 'reader_page.dart';
import 'mini_player_bar.dart';
import 'temp_library_provider.dart';

class VoxHomePage extends StatefulWidget {
  const VoxHomePage({super.key});

  @override
  State<VoxHomePage> createState() => _VoxHomePageState();
}

class _VoxHomePageState extends State<VoxHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  String _searchQuery = "";
  bool _isListening = false;

  @override
  void dispose() {
    _speech.stop();
    _searchController.dispose();
    super.dispose();
  }

  bool get _isAnonymous {
    final user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous;
  }

  Future<void> _openReader(String fileName, String content) async {
    final locale = context.read<LanguageProvider>().ttsLocale;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: context.read<TtsService>()),
            ChangeNotifierProvider.value(
              value: context.read<LanguageProvider>(),
            ),
          ],
          child: ReaderPage(title: fileName, content: content, locale: locale),
        ),
      ),
    );
  }

  void _listen() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Microphone permission denied"),
            backgroundColor: Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    bool available = await _speech.initialize(
      onError: (e) => setState(() => _isListening = false),
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
    if (available) {
      final langProvider = context.read<LanguageProvider>();
      setState(() => _isListening = true);
      _speech.listen(localeId: langProvider.sttLocale, onResult: (val) {});
    }
  }

  // ── Delete for Firestore (logged-in users) ────────────
  void _confirmDelete(BuildContext context, String docId, String fileName) {
    final lang = context.read<LanguageProvider>();
    final displayName = fileName.length > 40
        ? '${fileName.substring(0, 40)}...'
        : fileName;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const Icon(Icons.delete_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text(
              'Delete "$displayName"?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              lang.t('remove_library'),
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.grey[600]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(lang.t('cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(sheetCtx);
                      try {
                        await FirebaseFirestore.instance
                            .collection('library')
                            .doc(docId)
                            .delete();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '"$displayName" ${lang.t('deleted')}',
                              ),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: const Color(0xFF333333),
                              margin: const EdgeInsets.only(
                                bottom: 90,
                                left: 20,
                                right: 20,
                              ),
                            ),
                          );
                        }
                      } on FirebaseException catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e.code == 'unavailable'
                                    ? 'Cannot delete while offline'
                                    : 'Delete failed: ${e.message}',
                              ),
                              backgroundColor: const Color(0xFF333333),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(lang.t('delete_confirm')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Delete for temp/anonymous users ──────────────────
  void _confirmDeleteTemp(
    BuildContext context,
    String id,
    String fileName,
    TempLibraryProvider tempLibrary,
  ) {
    final lang = context.read<LanguageProvider>();
    final displayName = fileName.length > 40
        ? '${fileName.substring(0, 40)}...'
        : fileName;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const Icon(Icons.delete_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text(
              'Delete "$displayName"?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              lang.t('remove_library'),
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.grey[600]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(lang.t('cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      tempLibrary.remove(id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('"$displayName" ${lang.t('deleted')}'),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: const Color(0xFF333333),
                          margin: const EdgeInsets.only(
                            bottom: 90,
                            left: 20,
                            right: 20,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(lang.t('delete_confirm')),
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
    final lang = context.watch<LanguageProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Vox",
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    width: 180,
                    height: 38,
                    child: TextField(
                      controller: _searchController,
                      maxLength: 100,
                      onChanged: (v) =>
                          setState(() => _searchQuery = v.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: lang.t('search_hint'),
                        counterText: '',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.8),
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                lang.t('library'),
                style: const TextStyle(
                  fontSize: 18,
                  color: Color(0xFF9A9A3E),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                lang.t('tap_hint'),
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),

              // ── Guest temp warning banner ────────────────
              if (_isAnonymous) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.black54,
                        size: 15,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Guest mode — files are temporary. Create an account to save them.',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 8),

              // ── Library content ──────────────────────────
              Expanded(
                child: Consumer<TempLibraryProvider>(
                  builder: (context, tempLibrary, _) {
                    // Anonymous: show in-memory items
                    if (_isAnonymous) {
                      final items = tempLibrary.items.where((item) {
                        return item.fileName.toLowerCase().contains(
                          _searchQuery,
                        );
                      }).toList();

                      if (items.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.folder_off_outlined,
                                color: Colors.grey[400],
                                size: 48,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'No files yet.',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tap + to upload.\nFiles are temporary until you create an account.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1.1,
                            ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return GestureDetector(
                            onTap: () =>
                                _openReader(item.fileName, item.content),
                            onLongPress: () => _confirmDeleteTemp(
                              context,
                              item.id,
                              item.fileName,
                              tempLibrary,
                            ),
                            child: _buildFileCard(item.fileName, item.fileType),
                          );
                        },
                      );
                    }

                    // Logged in: Firestore stream
                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('library')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          final isOffline =
                              snapshot.error.toString().contains(
                                'unavailable',
                              ) ||
                              snapshot.error.toString().contains(
                                'Failed to get document',
                              );
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isOffline
                                      ? Icons.wifi_off
                                      : Icons.error_outline,
                                  color: Colors.grey[500],
                                  size: 40,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  isOffline
                                      ? 'You\'re offline.\nShowing cached library.'
                                      : 'Something went wrong.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final docs = snapshot.data!.docs.where((doc) {
                          final data =
                              doc.data() as Map<String, dynamic>? ?? {};
                          final name = (data['fileName'] as String? ?? '')
                              .toLowerCase();
                          return name.contains(_searchQuery);
                        }).toList();

                        if (docs.isEmpty) {
                          return Center(
                            child: Text(
                              lang.t('no_files'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          );
                        }

                        return GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 1.1,
                              ),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final data =
                                docs[index].data() as Map<String, dynamic>? ??
                                {};
                            final String name =
                                data['fileName'] as String? ?? 'File';
                            final String type =
                                data['fileType'] as String? ?? 'pdf';
                            final String content =
                                data['content'] as String? ?? '';
                            final String docId = docs[index].id;
                            return GestureDetector(
                              onTap: () => _openReader(name, content),
                              onLongPress: () =>
                                  _confirmDelete(context, docId, name),
                              child: _buildFileCard(name, type),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const MiniPlayerBar(),
            ],
          ),
        ),
      ),

      bottomNavigationBar: BottomAppBar(
        color: Colors.grey[850],
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 65,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(Icons.home, lang.t('nav_home'), Colors.white),
              _navItem(
                Icons.note_alt_outlined,
                lang.t('nav_notes'),
                Colors.grey[400]!,
                onTap: () => Navigator.pushNamed(context, '/notes'),
              ),
              const SizedBox(width: 48),
              _navItem(
                Icons.book,
                lang.t('nav_dictionary'),
                Colors.grey[400]!,
                onTap: () => Navigator.pushNamed(context, '/dictionary'),
              ),
              _navItem(
                Icons.menu,
                lang.t('nav_menu'),
                Colors.grey[400]!,
                onTap: () => Navigator.pushNamed(context, '/menu'),
              ),
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

  Widget _buildFileCard(String title, String type) {
    IconData iconData;
    Color iconColor;
    switch (type.toLowerCase()) {
      case 'pdf':
        iconData = Icons.picture_as_pdf;
        iconColor = Colors.red.shade400;
        break;
      case 'doc':
      case 'docx':
        iconData = Icons.description;
        iconColor = Colors.blue.shade400;
        break;
      case 'ppt':
      case 'pptx':
        iconData = Icons.slideshow;
        iconColor = Colors.orange.shade400;
        break;
      case 'txt':
        iconData = Icons.text_snippet;
        iconColor = Colors.grey.shade600;
        break;
      default:
        iconData = Icons.insert_drive_file;
        iconColor = Colors.grey.shade600;
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Icon(iconData, size: 28, color: iconColor),
          ),
        ],
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
