import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'language_provider.dart';
import 'tts_service.dart';
import 'reader_page.dart';
import 'mini_player_bar.dart';
import 'temp_library_provider.dart';
import 'ai_result_page.dart';
import 'main.dart';

class VoxHomePage extends StatefulWidget {
  const VoxHomePage({super.key});

  @override
  State<VoxHomePage> createState() => _VoxHomePageState();
}

class _VoxHomePageState extends State<VoxHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  String _searchQuery = '';
  bool _isListening = false;

  String? _resolvedUid;
  bool _isAnonymousUser = true;

  @override
  void initState() {
    super.initState();
    _resolveUser();
    // Show the chatbot exactly when the HomePage is presented
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showChatBotNotifier.value = true;
    });
  }

  @override
  void dispose() {
    _speech.stop();
    _searchController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  //  RESOLVE USER
  // ─────────────────────────────────────────────
  Future<void> _resolveUser() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _isAnonymousUser = true;
          _resolvedUid = null;
        });
      }
      return;
    }

    if (!user.isAnonymous) {
      if (mounted) {
        setState(() {
          _isAnonymousUser = false;
          _resolvedUid = user.uid;
        });
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final hasProfile = prefs.getBool('hasProfile') ?? false;

    if (!hasProfile) {
      if (mounted) {
        setState(() {
          _isAnonymousUser = true;
          _resolvedUid = null;
        });
      }
      return;
    }

    final uidDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (uidDoc.exists) {
      if (mounted) {
        setState(() {
          _isAnonymousUser = false;
          _resolvedUid = user.uid;
        });
      }
      return;
    }

    final savedEmail = prefs.getString('userEmail') ?? '';
    if (savedEmail.isNotEmpty) {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: savedEmail)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final docUid = query.docs.first.id;
        if (mounted) {
          setState(() {
            _isAnonymousUser = false;
            _resolvedUid = docUid;
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isAnonymousUser = true;
        _resolvedUid = null;
      });
    }
  }

  // ─────────────────────────────────────────────
  //  DOCUMENT OPTIONS (3 buttons)
  // ─────────────────────────────────────────────
  Future<void> _showDocumentOptions(String fileName, String content) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Text(
              fileName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              'What would you like to do?',
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
            const SizedBox(height: 20),
            _docOptionTile(
              ctx,
              icon: Icons.headphones_rounded,
              iconColor: const Color(0xFFD4B96A),
              title: 'Read Document',
              subtitle: 'Listen to the document read aloud',
              value: 'read',
            ),
            const SizedBox(height: 10),
            _docOptionTile(
              ctx,
              icon: Icons.summarize_outlined,
              iconColor: Colors.blue[300]!,
              title: 'Summarize',
              subtitle: 'Get an AI-powered summary of the document',
              value: 'summary',
            ),
            const SizedBox(height: 10),
            _docOptionTile(
              ctx,
              icon: Icons.style_outlined,
              iconColor: Colors.green[300]!,
              title: 'Generate Flashcards',
              subtitle: 'Create study flashcards from the document',
              value: 'flashcards',
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'read') {
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
            child: ReaderPage(
              title: fileName,
              content: content,
              locale: locale,
            ),
          ),
        ),
      );
    } else {
      // Show card count picker for flashcards
      int? cardCount;
      if (choice == 'flashcards') {
        cardCount = await _pickCardCount(context);
        if (cardCount == null || !mounted) return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AiResultPage(
            documentTitle: fileName,
            documentContent: content,
            mode: choice,
            cardCount: cardCount ?? 10,
          ),
        ),
      );
    }
  }

  Widget _docOptionTile(
    BuildContext ctx, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String value,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pop(ctx, value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  OPEN READER (kept for backward compatibility)
  // ─────────────────────────────────────────────
  Future<void> _openReader(String fileName, String content) async {
    await _showDocumentOptions(fileName, content);
  }

  // ─────────────────────────────────────────────
  //  VOICE SEARCH
  // ─────────────────────────────────────────────
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
            content: Text('Microphone permission denied'),
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
      _speech.listen(
        localeId: langProvider.sttLocale,
        onResult: (val) {
          setState(() {
            _searchQuery = val.recognizedWords.toLowerCase();
            _searchController.text = val.recognizedWords;
          });
        },
      );
    }
  }

  // ─────────────────────────────────────────────
  //  DELETE — Firestore (logged-in users)
  // ─────────────────────────────────────────────
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
                        // Use _resolvedUid (may differ from Firebase auth UID
                        // for anonymous users whose profile was created by email)
                        final uid =
                            _resolvedUid ??
                            FirebaseAuth.instance.currentUser?.uid;
                        final libRef = FirebaseFirestore.instance
                            .collection('library')
                            .doc(docId);

                        await libRef.delete();

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

  // ─────────────────────────────────────────────
  //  DELETE — temp/anonymous users
  // ─────────────────────────────────────────────
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

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
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
              // ── Header ──────────────────────────────────
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
                        suffixIcon: GestureDetector(
                          onTap: _listen,
                          child: Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            size: 18,
                            color: _isListening
                                ? Colors.redAccent
                                : Colors.black54,
                          ),
                        ),
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

              // ── Guest banner ─────────────────────────────
              if (_isAnonymousUser) ...[
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
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.black54, size: 15),
                      SizedBox(width: 8),
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
                    // ── Guest: in-memory items ───────────────
                    if (_isAnonymousUser) {
                      final items = tempLibrary.items
                          .where(
                            (item) => item.fileName.toLowerCase().contains(
                              _searchQuery,
                            ),
                          )
                          .toList();

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

                    // ── Logged in: Firestore filtered by userId ──
                    if (_resolvedUid == null) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return StreamBuilder<QuerySnapshot>(
                      // FIX: removed .orderBy() to avoid requiring a composite
                      // Firestore index. Docs are sorted client-side below.
                      stream: FirebaseFirestore.instance
                          .collection('library')
                          .where('userId', isEqualTo: _resolvedUid)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          debugPrint('🔴 Firestore error: ${snapshot.error}');
                          final isOffline = snapshot.error.toString().contains(
                            'unavailable',
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

                        // Filter by search query
                        final docs = snapshot.data!.docs.where((doc) {
                          final data =
                              doc.data() as Map<String, dynamic>? ?? {};
                          final name = (data['fileName'] as String? ?? '')
                              .toLowerCase();
                          return name.contains(_searchQuery);
                        }).toList();

                        // FIX: sort client-side by timestamp descending
                        // (replaces the removed .orderBy() on the query)
                        docs.sort((a, b) {
                          final aTs =
                              (a.data() as Map<String, dynamic>)['timestamp']
                                  as Timestamp?;
                          final bTs =
                              (b.data() as Map<String, dynamic>)['timestamp']
                                  as Timestamp?;
                          if (aTs == null && bTs == null) return 0;
                          if (aTs == null) return 1;
                          if (bTs == null) return -1;
                          return bTs.compareTo(aTs);
                        });

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

  // ── Card count picker ─────────────────────────
  Future<int?> _pickCardCount(BuildContext context) async {
    int selected = 10;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFFF3E5AB),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'How many flashcards?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$selected cards',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF7A6130),
                ),
              ),
              Slider(
                value: selected.toDouble(),
                min: 5,
                max: 20,
                divisions: 15,
                activeColor: Colors.black,
                inactiveColor: Colors.grey[300],
                onChanged: (v) => setDialogState(() => selected = v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '5',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  Text(
                    '20',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.black54),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: const Color(0xFFF3E5AB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Generate'),
            ),
          ],
        ),
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
