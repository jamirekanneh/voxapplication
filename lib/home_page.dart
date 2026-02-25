import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

class VoxHomePage extends StatefulWidget {
  const VoxHomePage({super.key});

  @override
  State<VoxHomePage> createState() => _VoxHomePageState();
}

class _VoxHomePageState extends State<VoxHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  String _searchQuery = "";
  bool _isListening = false;

  String? _nowReadingTitle;
  String? _nowReadingContent;
  bool _isPlaying = false;
  bool _showReadingBar = false;
  double _readingProgress = 0.0;
  double _currentSpeechRate = 0.5;

  @override
  void initState() {
    super.initState();
    _initTTS();
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  void _initTTS() async {
    await _tts.setLanguage("en-US");
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(_currentSpeechRate);
    _tts.setCompletionHandler(() {
      if (mounted)
        setState(() {
          _isPlaying = false;
          _readingProgress = 1.0;
        });
    });
    _tts.setProgressHandler((text, start, end, word) {
      final total = text.length;
      if (total > 0 && mounted) setState(() => _readingProgress = end / total);
    });
  }

  Future<void> _openFileAndRead(String fileName, String content) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF3E5AB),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx2, sc) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  controller: sc,
                  child: Text(
                    content.isNotEmpty
                        ? content
                        : "File preview not available.\nPress Start Reading to listen.",
                    style: const TextStyle(fontSize: 15, height: 1.7),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("Start Reading"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _startReadingFile(
                      fileName,
                      content.isNotEmpty ? content : "Reading $fileName now.",
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Delete confirmation ──
  void _confirmDelete(String docId, String fileName) {
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
              'Delete "$fileName"?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              "This will remove it from your library.",
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
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(sheetCtx);
                      await FirebaseFirestore.instance
                          .collection('library')
                          .doc(docId)
                          .delete();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('"$fileName" deleted'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Colors.grey[850],
                            margin: const EdgeInsets.only(
                              bottom: 90,
                              left: 20,
                              right: 20,
                            ),
                          ),
                        );
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
                    child: const Text("Delete"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startReadingFile(String fileName, String text) async {
    await _tts.stop();
    await _tts.setSpeechRate(_currentSpeechRate);
    setState(() {
      _nowReadingTitle = fileName;
      _nowReadingContent = text;
      _isPlaying = true;
      _showReadingBar = true;
      _readingProgress = 0.0;
    });
    await _tts.speak(text);
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _tts.pause();
      setState(() => _isPlaying = false);
    } else {
      if (_nowReadingContent != null) {
        await _tts.speak(_nowReadingContent!);
        setState(() => _isPlaying = true);
      }
    }
  }

  Future<void> _stopReading() async {
    await _tts.stop();
    setState(() {
      _showReadingBar = false;
      _nowReadingTitle = null;
      _nowReadingContent = null;
      _isPlaying = false;
      _readingProgress = 0.0;
      _currentSpeechRate = 0.5;
    });
    await _tts.setSpeechRate(0.5);
  }

  Future<void> _fastForward() async {
    await _tts.stop();
    _currentSpeechRate = (_currentSpeechRate + 0.2).clamp(0.1, 2.0);
    await _tts.setSpeechRate(_currentSpeechRate);
    if (_nowReadingContent != null) {
      await _tts.speak(_nowReadingContent!);
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _rewind() async {
    await _tts.stop();
    _currentSpeechRate = (_currentSpeechRate - 0.2).clamp(0.1, 2.0);
    await _tts.setSpeechRate(_currentSpeechRate);
    if (_nowReadingContent != null) {
      await _tts.speak(_nowReadingContent!);
      setState(() {
        _isPlaying = true;
        _readingProgress = 0.0;
      });
    }
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            String command = val.recognizedWords.toLowerCase();
            if (command.contains("open")) {
              String targetFile = command.replaceFirst("open ", "").trim();
              _startReadingFile(
                targetFile,
                "Opening $targetFile and starting automated reading now.",
              );
            }
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top bar
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
                      onChanged: (v) =>
                          setState(() => _searchQuery = v.toLowerCase()),
                      decoration: InputDecoration(
                        hintText: "Search files...",
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

              const Text(
                "Library",
                style: TextStyle(
                  fontSize: 18,
                  color: Color(0xFF9A9A3E),
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              // Hint for delete
              Text(
                "Tap to open • Long press to delete",
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),

              const SizedBox(height: 8),

              // File grid
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('library')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    var docs = snapshot.data!.docs.where((doc) {
                      String name =
                          (doc.data() as Map<String, dynamic>)['fileName'] ??
                          "";
                      return name.toLowerCase().contains(_searchQuery);
                    }).toList();

                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          "No files yet.\nTap + to upload.",
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
                            childAspectRatio: 1.1, // Compact square-ish cards
                          ),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        var data = docs[index].data() as Map<String, dynamic>;
                        String name = data['fileName'] ?? 'File';
                        String type = data['fileType'] ?? 'pdf';
                        String docId = docs[index].id;

                        return GestureDetector(
                          onTap: () => _openFileAndRead(name, ""),
                          onLongPress: () => _confirmDelete(docId, name),
                          child: _buildFileCard(name, type),
                        );
                      },
                    );
                  },
                ),
              ),

              // Spotify reading bar
              if (_showReadingBar) _buildReadingBar(),
            ],
          ),
        ),
      ),

      // Grey bottom nav
      bottomNavigationBar: BottomAppBar(
        color: Colors.grey[850],
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 65,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(Icons.home, "Home", Colors.white),
              _navItem(
                Icons.note_alt_outlined,
                "Notes",
                Colors.grey[400]!,
                onTap: () => Navigator.pushNamed(context, '/notes'),
              ),
              const SizedBox(width: 48),
              _navItem(
                Icons.book,
                "Dictionary",
                Colors.grey[400]!,
                onTap: () => Navigator.pushNamed(context, '/dictionary'),
              ),
              _navItem(
                Icons.menu,
                "Menu",
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

  // ── Compact file card: title top, icon bottom, no empty space ──
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween, // No empty gap
        children: [
          // Filename top
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
          // Icon bottom-right
          Align(
            alignment: Alignment.bottomRight,
            child: Icon(iconData, size: 28, color: iconColor),
          ),
        ],
      ),
    );
  }

  Widget _buildReadingBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: LinearProgressIndicator(
              value: _readingProgress,
              backgroundColor: Colors.grey[700],
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF70E1C1),
              ),
              minHeight: 3,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.description,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _nowReadingTitle ?? "",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        "${_currentSpeechRate.toStringAsFixed(1)}x speed",
                        style: TextStyle(color: Colors.grey[400], fontSize: 10),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: _rewind,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFF70E1C1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.black,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: _fastForward,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  onPressed: _stopReading,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
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
