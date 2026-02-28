import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'language_provider.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final stt.SpeechToText _speech = stt.SpeechToText();

  // Title
  bool _isListeningTitle = false;
  final TextEditingController _titleController = TextEditingController();

  // Content — single editable controller, speech fills it, user can also type/edit
  bool _isListeningContent = false;
  final TextEditingController _contentController = TextEditingController();

  String get _userId => FirebaseAuth.instance.currentUser?.uid ?? "anonymous";

  @override
  void dispose() {
    _speech.stop();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // ── Mic for title ──
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
        if (s == 'done' || s == 'notListening')
          setState(() => _isListeningTitle = false);
      },
    );
    if (available) {
      setState(() => _isListeningTitle = true);
      _speech.listen(
        localeId: langProvider.sttLocale,
        onResult: (val) {
          _titleController.text = val.recognizedWords;
          _titleController.selection = TextSelection.fromPosition(
            TextPosition(offset: _titleController.text.length),
          );
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
      );
    }
  }

  // ── Mic for content — appends to existing text so user can speak, then type more ──
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
        if (s == 'done' || s == 'notListening')
          setState(() => _isListeningContent = false);
      },
    );
    if (available) {
      // Remember what was typed before speaking so we can append
      final existingText = _contentController.text;
      final prefix = existingText.isNotEmpty ? "$existingText " : "";

      setState(() => _isListeningContent = true);
      _speech.listen(
        localeId: langProvider.sttLocale,
        onResult: (val) {
          final spoken = val.recognizedWords;
          _contentController.text = "$prefix$spoken";
          _contentController.selection = TextSelection.fromPosition(
            TextPosition(offset: _contentController.text.length),
          );
          setState(() {});
        },
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
      );
    }
  }

  Future<void> _saveNote() async {
    final content = _contentController.text.trim();
    final title = _titleController.text.trim();

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please add some content before saving."),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 30, left: 20, right: 20),
        ),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('notes').add({
        'userId': _userId,
        'title': title.isNotEmpty ? title : "Note",
        'content': content,
        'timestamp': FieldValue.serverTimestamp(),
      });
      setState(() {
        _contentController.clear();
        _titleController.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Note saved!"),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF333333),
            margin: EdgeInsets.only(bottom: 30, left: 20, right: 20),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error saving: $e"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
          ),
        );
      }
    }
  }

  Future<void> _deleteNote(String docId) async {
    await FirebaseFirestore.instance.collection('notes').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = context.watch<LanguageProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      appBar: AppBar(
        title: const Text(
          "Notes",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  langProvider.selectedLanguage,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title field with mic ──
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          hintText: _isListeningTitle
                              ? "Listening for title..."
                              : "Note title (optional)",
                          filled: true,
                          fillColor: _isListeningTitle
                              ? Colors.grey[200]
                              : Colors.white.withOpacity(0.7),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
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
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: _isListeningTitle
                              ? Colors.red
                              : Colors.grey[700],
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _isListeningTitle ? Icons.stop : Icons.mic,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // ── Content area: editable text field with mic button inside ──
                Stack(
                  children: [
                    TextField(
                      controller: _contentController,
                      maxLines: 6,
                      minLines: 4,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: _isListeningContent
                            ? "Listening in ${langProvider.selectedLanguage}..."
                            : "Speak or type your note here...",
                        filled: true,
                        fillColor: _isListeningContent
                            ? Colors.grey[200]
                            : Colors.white.withOpacity(0.7),
                        contentPadding: const EdgeInsets.fromLTRB(
                          16,
                          14,
                          56,
                          14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: _isListeningContent
                              ? BorderSide(color: Colors.grey[600]!, width: 1.5)
                              : BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: Colors.grey[400]!,
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                    // Mic button inside the text field (bottom-right)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: GestureDetector(
                        onTap: _listenForContent,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _isListeningContent
                                ? Colors.red
                                : Colors.grey[700],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _isListeningContent ? Icons.stop : Icons.mic,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Save & Clear ──
                Row(
                  children: [
                    if (_contentController.text.isNotEmpty)
                      Expanded(
                        flex: 1,
                        child: OutlinedButton(
                          onPressed: () =>
                              setState(() => _contentController.clear()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black,
                            side: BorderSide(color: Colors.grey[400]!),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text("Clear"),
                        ),
                      ),
                    if (_contentController.text.isNotEmpty)
                      const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _contentController.text.trim().isNotEmpty
                            ? _saveNote
                            : null,
                        icon: const Icon(Icons.save_alt),
                        label: const Text("Save Note"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[400],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(child: Divider(color: Colors.grey[400])),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    "Saved Notes",
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: Colors.grey[400])),
              ],
            ),
          ),

          // ── Saved notes ──
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notes')
                  .where('userId', isEqualTo: _userId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      "Error: ${snapshot.error}",
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs.toList()
                  ..sort((a, b) {
                    final aTime = (a.data() as Map)['timestamp'];
                    final bTime = (b.data() as Map)['timestamp'];
                    if (aTime == null || bTime == null) return 0;
                    return bTime.compareTo(aTime);
                  });

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      "No notes yet. Start speaking or typing!",
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (ctx, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final title = data['title'] ?? 'Note';
                    final content = data['content'] ?? '';
                    final docId = docs[i].id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.grey,
                          ),
                          onPressed: () => _deleteNote(docId),
                        ),
                      ),
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
              _navItem(
                Icons.home,
                "Home",
                Colors.grey[400]!,
                onTap: () => Navigator.pushReplacementNamed(context, '/home'),
              ),
              _navItem(Icons.note_alt_outlined, "Notes", Colors.white),
              const SizedBox(width: 48),
              _navItem(
                Icons.book,
                "Dictionary",
                Colors.grey[400]!,
                onTap: () =>
                    Navigator.pushReplacementNamed(context, '/dictionary'),
              ),
              _navItem(
                Icons.menu,
                "Menu",
                Colors.grey[400]!,
                onTap: () => Navigator.pushReplacementNamed(context, '/menu'),
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
