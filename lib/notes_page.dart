import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'language_provider.dart';
import 'temp_notes_provider.dart';

const int _kMaxTitleLength = 100;
const int _kMaxContentLength = 5000;

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListeningTitle = false;
  bool _isListeningContent = false;
  bool _isSaving = false;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  String? get _userId => FirebaseAuth.instance.currentUser?.uid;
  bool get _isAnonymous {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return true;
    return user.isAnonymous;
  }

  @override
  void dispose() {
    _speech.stop();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // ── Speech for title ──────────────────────────────────
  Future<void> _listenForTitle() async {
    final langProvider = context.read<LanguageProvider>();
    if (_isListeningTitle) {
      await _speech.stop();
      setState(() => _isListeningTitle = false);
      return;
    }
    if (_isListeningContent) {
      await _speech.stop();
      setState(() => _isListeningContent = false);
    }
    bool available = await _speech.initialize(
      onError: (e) => setState(() => _isListeningTitle = false),
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) setState(() => _isListeningTitle = false);
        }
      },
    );
    if (available) {
      setState(() => _isListeningTitle = true);
      _speech.listen(
        localeId: langProvider.sttLocale,
        onResult: (val) {
          final text = val.recognizedWords.trim();
          _titleController.text = text.length > _kMaxTitleLength
              ? text.substring(0, _kMaxTitleLength)
              : text;
          _titleController.selection = TextSelection.fromPosition(
              TextPosition(offset: _titleController.text.length));
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
      );
    }
  }

  // ── Speech for content ────────────────────────────────
  Future<void> _listenForContent() async {
    final langProvider = context.read<LanguageProvider>();
    if (_isListeningContent) {
      await _speech.stop();
      setState(() => _isListeningContent = false);
      return;
    }
    if (_isListeningTitle) {
      await _speech.stop();
      setState(() => _isListeningTitle = false);
    }
    bool available = await _speech.initialize(
      onError: (e) => setState(() => _isListeningContent = false),
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) setState(() => _isListeningContent = false);
        }
      },
    );
    if (available) {
      final existingText = _contentController.text;
      final prefix = existingText.isNotEmpty ? '$existingText ' : '';
      setState(() => _isListeningContent = true);
      _speech.listen(
        localeId: langProvider.sttLocale,
        onResult: (val) {
          final combined = '$prefix${val.recognizedWords}';
          _contentController.text = combined.length > _kMaxContentLength
              ? combined.substring(0, _kMaxContentLength)
              : combined;
          _contentController.selection = TextSelection.fromPosition(
              TextPosition(offset: _contentController.text.length));
          setState(() {});
        },
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
      );
    }
  }

  // ── Save note ─────────────────────────────────────────
  Future<void> _saveNote(LanguageProvider lang) async {
    final content = _contentController.text.trim();
    final rawTitle = _titleController.text.trim();
    final title = rawTitle.isNotEmpty ? rawTitle : 'Note';

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(lang.t('add_content')),
        backgroundColor: const Color(0xFF333333),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
      ));
      return;
    }

    if (title.length > _kMaxTitleLength ||
        content.length > _kMaxContentLength) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Note is too long. Please shorten it.'),
        backgroundColor: Color(0xFF333333),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: 30, left: 20, right: 20),
      ));
      return;
    }

    setState(() => _isSaving = true);

    try {
      if (_isAnonymous) {
        // ── Anonymous: store in memory ──────────────────
        final tempNotes = context.read<TempNotesProvider>();
        tempNotes.add(title, content);
        if (mounted) {
          setState(() {
            _contentController.clear();
            _titleController.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Note saved temporarily. Create an account to keep it.'),
            backgroundColor: Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 30, left: 20, right: 20),
          ));
        }
      } else {
        // ── Logged in: save to Firestore ────────────────
        await FirebaseFirestore.instance.collection('notes').add({
          'userId': _userId,
          'title': title,
          'content': content,
          'timestamp': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          setState(() {
            _contentController.clear();
            _titleController.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(lang.t('note_saved')),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF333333),
            margin:
                const EdgeInsets.only(bottom: 30, left: 20, right: 20),
          ));
        }
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.code == 'unavailable'
              ? 'No internet. Note will sync when back online.'
              : '${lang.t('error_saving')} ${e.message}'),
          backgroundColor: const Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${lang.t('error_saving')} $e'),
          backgroundColor: const Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Delete Firestore note ─────────────────────────────
  Future<void> _deleteNote(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notes')
          .doc(docId)
          .delete();
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.code == 'unavailable'
              ? 'Cannot delete while offline.'
              : 'Delete failed: ${e.message}'),
          backgroundColor: const Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Delete temp note ──────────────────────────────────
  void _deleteTempNote(String id, TempNotesProvider tempNotes) {
    tempNotes.remove(id);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Note deleted.'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xFF333333),
      margin: EdgeInsets.only(bottom: 30, left: 20, right: 20),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      appBar: AppBar(
        title: Text(lang.t('notes_title'),
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(20)),
                child: Text(lang.selectedLanguage,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Guest banner ──────────────────────────
                if (_isAnonymous) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.black.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.black54, size: 15),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Guest mode — notes are temporary. Create an account to keep them.',
                            style: TextStyle(
                                color: Colors.black54,
                                fontSize: 11,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── Title field ───────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        maxLength: _kMaxTitleLength,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: _isListeningTitle
                              ? lang.t('listening_title')
                              : lang.t('title_hint'),
                          counterText: '',
                          filled: true,
                          fillColor: _isListeningTitle
                              ? Colors.grey[200]
                              : Colors.white.withOpacity(0.7),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _listenForTitle,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 46, height: 46,
                        decoration: BoxDecoration(
                          color: _isListeningTitle
                              ? Colors.red
                              : Colors.grey[700],
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _isListeningTitle ? Icons.stop : Icons.mic,
                          color: Colors.white, size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── Content field ─────────────────────────
                Stack(
                  children: [
                    TextField(
                      controller: _contentController,
                      maxLines: 6,
                      minLines: 4,
                      maxLength: _kMaxContentLength,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: _isListeningContent
                            ? '${lang.t('listening_content')} ${lang.selectedLanguage}...'
                            : lang.t('content_hint'),
                        counterText: '',
                        filled: true,
                        fillColor: _isListeningContent
                            ? Colors.grey[200]
                            : Colors.white.withOpacity(0.7),
                        contentPadding:
                            const EdgeInsets.fromLTRB(16, 14, 56, 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: _isListeningContent
                              ? BorderSide(
                                  color: Colors.grey[600]!, width: 1.5)
                              : BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                              color: Colors.grey[400]!, width: 1),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8, bottom: 8,
                      child: GestureDetector(
                        onTap: _listenForContent,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: _isListeningContent
                                ? Colors.red
                                : Colors.grey[700],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _isListeningContent ? Icons.stop : Icons.mic,
                            color: Colors.white, size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Save & Clear buttons ──────────────────
                Row(
                  children: [
                    if (_contentController.text.isNotEmpty) ...[
                      Expanded(
                        flex: 1,
                        child: OutlinedButton(
                          onPressed: () =>
                              setState(() => _contentController.clear()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black,
                            side: BorderSide(color: Colors.grey[400]!),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(lang.t('clear')),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: (!_isSaving &&
                                _contentController.text.trim().isNotEmpty)
                            ? () => _saveNote(lang)
                            : null,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(Icons.save_alt),
                        label: Text(lang.t('save_note')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[400],
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Divider ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(child: Divider(color: Colors.grey[400])),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(lang.t('saved_notes'),
                      style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
                Expanded(child: Divider(color: Colors.grey[400])),
              ],
            ),
          ),

          // ── Notes list ────────────────────────────────
          Expanded(
            child: Consumer<TempNotesProvider>(
              builder: (context, tempNotes, _) {

                // Anonymous: show in-memory notes
                if (_isAnonymous) {
                  if (tempNotes.notes.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.note_outlined,
                              color: Colors.grey[400], size: 44),
                          const SizedBox(height: 12),
                          Text(lang.t('no_notes'),
                              style:
                                  TextStyle(color: Colors.grey[500])),
                          const SizedBox(height: 6),
                          Text(
                            'Notes are temporary in guest mode.',
                            style: TextStyle(
                                color: Colors.grey[400], fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    itemCount: tempNotes.notes.length,
                    itemBuilder: (ctx, i) {
                      final note = tempNotes.notes[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(note.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('temp',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.black45,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          subtitle: Text(note.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.grey),
                            onPressed: () =>
                                _deleteTempNote(note.id, tempNotes),
                          ),
                        ),
                      );
                    },
                  );
                }

                // Logged in: Firestore stream
                if (_userId == null) {
                  return Center(
                    child: Text('Sign in to see your notes.',
                        style: TextStyle(color: Colors.grey[500])),
                  );
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('notes')
                      .where('userId', isEqualTo: _userId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      final isOffline = snapshot.error
                          .toString()
                          .contains('unavailable');
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                isOffline
                                    ? Icons.wifi_off
                                    : Icons.error_outline,
                                color: Colors.grey[500],
                                size: 36),
                            const SizedBox(height: 10),
                            Text(
                              isOffline
                                  ? 'You\'re offline.\nShowing cached notes.'
                                  : 'Could not load notes.',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }

                    final docs = snapshot.data!.docs.toList()
                      ..sort((a, b) {
                        final aT = (a.data() as Map)['timestamp']
                            as Timestamp?;
                        final bT = (b.data() as Map)['timestamp']
                            as Timestamp?;
                        if (aT == null || bT == null) return 0;
                        return bT.compareTo(aT);
                      });

                    if (docs.isEmpty) {
                      return Center(
                        child: Text(lang.t('no_notes'),
                            style:
                                TextStyle(color: Colors.grey[500])),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      itemCount: docs.length,
                      itemBuilder: (ctx, i) {
                        final data = docs[i].data()
                            as Map<String, dynamic>? ?? {};
                        final title =
                            (data['title'] as String? ?? 'Note')
                                .trim();
                        final content =
                            (data['content'] as String? ?? '')
                                .trim();
                        final docId = docs[i].id;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            title: Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            subtitle: Text(content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    const TextStyle(fontSize: 12)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.grey),
                              onPressed: () => _deleteNote(docId),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
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
              _navItem(Icons.home, lang.t('nav_home'), Colors.grey[400]!,
                  onTap: () => Navigator.pushReplacementNamed(
                      context, '/home')),
              _navItem(Icons.note_alt_outlined, lang.t('nav_notes'),
                  Colors.white),
              const SizedBox(width: 48),
              _navItem(Icons.book, lang.t('nav_dictionary'),
                  Colors.grey[400]!,
                  onTap: () => Navigator.pushReplacementNamed(
                      context, '/dictionary')),
              _navItem(Icons.menu, lang.t('nav_menu'), Colors.grey[400]!,
                  onTap: () => Navigator.pushReplacementNamed(
                      context, '/menu')),
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

  Widget _navItem(IconData icon, String label, Color color,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}