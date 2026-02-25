import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _transcribedText = "";
  String _noteTitle = "";
  final TextEditingController _titleController = TextEditingController();

  // Use UID — not email — so notes are truly per-user
  String get _userId => FirebaseAuth.instance.currentUser?.uid ?? "anonymous";

  @override
  void dispose() {
    _speech.stop();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      bool available = await _speech.initialize(
        onError: (e) => setState(() => _isListening = false),
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            setState(() => _isListening = false);
          }
        },
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() => _transcribedText = val.recognizedWords);
          },
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
        );
      }
    }
  }

  Future<void> _saveNote() async {
    if (_transcribedText.trim().isEmpty) return;

    // Save under userId (UID) so only this user sees their notes
    await FirebaseFirestore.instance.collection('notes').add({
      'userId': _userId, // UID not email
      'title': _noteTitle.isNotEmpty ? _noteTitle : "Note",
      'content': _transcribedText,
      'timestamp': FieldValue.serverTimestamp(),
    });

    setState(() {
      _transcribedText = "";
      _noteTitle = "";
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
  }

  Future<void> _deleteNote(String docId) async {
    await FirebaseFirestore.instance.collection('notes').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      appBar: AppBar(
        title: const Text(
          "Notes",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          // New note area
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _titleController,
                  onChanged: (v) => _noteTitle = v,
                  decoration: InputDecoration(
                    hintText: "Note title (optional)",
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.7),
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
                const SizedBox(height: 10),

                GestureDetector(
                  onTap: _toggleListening,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 130),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _isListening
                          ? Colors.grey[200]
                          : Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isListening
                            ? Colors.grey[600]!
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: _transcribedText.isEmpty
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isListening
                                    ? Icons.graphic_eq
                                    : Icons.mic_none,
                                size: 40,
                                color: _isListening
                                    ? Colors.grey[700]
                                    : Colors.grey[400],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isListening
                                    ? "Listening... tap to stop"
                                    : "Tap to speak your note",
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            _transcribedText,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.6,
                              color: Colors.black87,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _toggleListening,
                        icon: Icon(_isListening ? Icons.stop : Icons.mic),
                        label: Text(_isListening ? "Stop" : "Speak"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isListening
                              ? Colors.grey[700]
                              : Colors.grey[600],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _transcribedText.trim().isEmpty
                            ? null
                            : _saveNote,
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

                if (_transcribedText.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _transcribedText = ""),
                    child: Text(
                      "Clear",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),

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

          // Saved notes — filtered by UID
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notes')
                  .where('userId', isEqualTo: _userId) // UID filter
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      "No notes yet. Start speaking!",
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
    );
  }
}
