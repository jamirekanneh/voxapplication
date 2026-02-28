import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'language_provider.dart';

// ─────────────────────────────────────────────
//  Global TTS state — survives page navigation
// ─────────────────────────────────────────────
class _ReaderState {
  static final FlutterTts tts = FlutterTts();
  static String? title;
  static String? content;
  static bool isPlaying = false;
  static bool isVisible = false;
  static double speechRate = 1.0;
  static double progress = 0.0;
  static int wordStart = 0;
  static int wordEnd = 0;
  static VoidCallback? onStateChanged;

  static void notify() => onStateChanged?.call();

  static Future<void> play(String t, String c, String locale) async {
    await tts.stop();
    title = t;
    content = c;
    isPlaying = true;
    isVisible = true;
    progress = 0.0;
    wordStart = 0;
    wordEnd = 0;
    await tts.setLanguage(locale);
    await tts.setSpeechRate(speechRate);
    await tts.setPitch(1.0);
    tts.setProgressHandler((text, start, end, word) {
      final total = text.length;
      if (total > 0) {
        progress = end / total;
        wordStart = start;
        wordEnd = end;
      }
      notify();
    });
    tts.setCompletionHandler(() {
      isPlaying = false;
      progress = 1.0;
      notify();
    });
    await tts.speak(c);
    notify();
  }

  static Future<void> togglePause(String locale) async {
    if (isPlaying) {
      await tts.pause();
      isPlaying = false;
    } else {
      if (content != null) {
        await tts.setLanguage(locale);
        await tts.speak(content!);
        isPlaying = true;
      }
    }
    notify();
  }

  // FIX 2: stop() now properly hides the bar
  static Future<void> stop() async {
    await tts.stop();
    isPlaying = false;
    isVisible = false;
    title = null;
    content = null;
    progress = 0.0;
    wordStart = 0;
    wordEnd = 0;
    notify();
  }

  // FIX 3: setRate just changes rate without restarting from beginning
  static Future<void> setRate(double rate, String locale) async {
    speechRate = rate.clamp(0.1, 2.0);
    await tts.setSpeechRate(speechRate);
    // Only restart if currently playing — Android requires stop/speak to apply rate
    if (isPlaying && content != null) {
      await tts.stop();
      await tts.setLanguage(locale);
      await tts.speak(content!);
    }
    notify();
  }
}

// ─────────────────────────────────────────────
//  Reader full-screen page
// ─────────────────────────────────────────────
class ReaderPage extends StatefulWidget {
  final String title;
  final String content;
  final String locale;

  const ReaderPage({
    super.key,
    required this.title,
    required this.content,
    required this.locale,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _ReaderState.onStateChanged = () {
      if (mounted) setState(() {});
    };
    if (!_ReaderState.isPlaying || _ReaderState.title != widget.title) {
      _ReaderState.play(widget.title, widget.content, widget.locale);
    }
  }

  @override
  void dispose() {
    _ReaderState.onStateChanged = null;
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildHighlightedText() {
    final text = widget.content;
    if (text.isEmpty) {
      return const Text(
        "No text content available for this file.",
        style: TextStyle(fontSize: 16, height: 1.8, color: Colors.black54),
      );
    }

    final start = _ReaderState.wordStart;
    final end = _ReaderState.wordEnd.clamp(0, text.length);

    if (start >= text.length || start >= end) {
      return Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          height: 1.8,
          color: Colors.black87,
        ),
      );
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 16,
          height: 1.8,
          color: Colors.black87,
        ),
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: const TextStyle(
              backgroundColor: Color(0xFFB3C8FF),
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LanguageProvider>().ttsLocale;
    final rate = _ReaderState.speechRate;

    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.keyboard_arrow_down, size: 32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // ── Progress bar ──
            LinearProgressIndicator(
              value: _ReaderState.progress,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFD4B96A),
              ),
              minHeight: 3,
            ),

            // ── Scrollable text with word highlight ──
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: _buildHighlightedText(),
              ),
            ),

            // ── Player controls ──
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  // Speed buttons
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text(
                          "Speed",
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(width: 12),
                        ...[0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map(
                          (s) => GestureDetector(
                            onTap: () => _ReaderState.setRate(s, locale),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: (rate - s).abs() < 0.01
                                    ? const Color(0xFFD4B96A)
                                    : Colors.grey[700],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                "${s}x",
                                style: TextStyle(
                                  color: (rate - s).abs() < 0.01
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Playback controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.replay,
                          color: Colors.white70,
                          size: 32,
                        ),
                        onPressed: () => _ReaderState.play(
                          widget.title,
                          widget.content,
                          locale,
                        ),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => _ReaderState.togglePause(locale),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: Color(0xFFD4B96A),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _ReaderState.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.black,
                            size: 34,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(
                          Icons.stop_circle_outlined,
                          color: Colors.white70,
                          size: 32,
                        ),
                        onPressed: () async {
                          await _ReaderState.stop();
                          if (mounted) Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Home Page
// ─────────────────────────────────────────────
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
  void initState() {
    super.initState();
    _ReaderState.onStateChanged = () {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  Future<void> _openReader(String fileName, String content) async {
    final locale = context.read<LanguageProvider>().ttsLocale;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<LanguageProvider>(),
          child: ReaderPage(title: fileName, content: content, locale: locale),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // FIX 1: request mic permission before STT
  void _listen() async {
    if (_isListening) {
      setState(() => _isListening = false);
      _speech.stop();
      return;
    }

    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Microphone permission denied"),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    bool available = await _speech.initialize(
      onError: (e) => setState(() => _isListening = false),
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          setState(() => _isListening = false);
        }
      },
    );

    if (available) {
      final langProvider = context.read<LanguageProvider>();
      setState(() => _isListening = true);
      _speech.listen(
        localeId: langProvider.sttLocale,
        onResult: (val) {
          setState(() => _isListening = false);
        },
      );
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LanguageProvider>().ttsLocale;

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

              Text(
                "Tap to read • Long press to delete",
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
                            childAspectRatio: 1.1,
                          ),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final String name = data['fileName'] ?? 'File';
                        final String type = data['fileType'] ?? 'pdf';
                        final String content = data['content'] ?? '';
                        final String docId = docs[index].id;

                        return GestureDetector(
                          onTap: () => _openReader(name, content),
                          onLongPress: () => _confirmDelete(docId, name),
                          child: _buildFileCard(name, type),
                        );
                      },
                    );
                  },
                ),
              ),

              // ── Minimized reading bar ──
              if (_ReaderState.isVisible) _buildMiniBar(locale),
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

  // ── Minimized bar ──
  Widget _buildMiniBar(String locale) {
    return GestureDetector(
      onTap: () {
        if (_ReaderState.title != null && _ReaderState.content != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider.value(
                value: context.read<LanguageProvider>(),
                child: ReaderPage(
                  title: _ReaderState.title!,
                  content: _ReaderState.content!,
                  locale: locale,
                ),
              ),
            ),
          ).then((_) {
            if (mounted) setState(() {});
          });
        }
      },
      child: Container(
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: LinearProgressIndicator(
                value: _ReaderState.progress,
                backgroundColor: Colors.grey[700],
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFD4B96A),
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
                          _ReaderState.title ?? "",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "${_ReaderState.speechRate.toStringAsFixed(2)}x speed",
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Decrease speed
                  IconButton(
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.white70,
                      size: 20,
                    ),
                    onPressed: () => _ReaderState.setRate(
                      _ReaderState.speechRate - 0.25,
                      locale,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 6),
                  // Play/Pause
                  GestureDetector(
                    onTap: () => _ReaderState.togglePause(locale),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: Color(0xFFD4B96A),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _ReaderState.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.black,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Increase speed
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: Colors.white70,
                      size: 20,
                    ),
                    onPressed: () => _ReaderState.setRate(
                      _ReaderState.speechRate + 0.25,
                      locale,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 4),
                  // FIX 2: X button — wrapped in GestureDetector to prevent
                  // tap from bubbling up to the parent GestureDetector (open reader)
                  GestureDetector(
                    onTap: () async {
                      await _ReaderState.stop();
                      if (mounted) setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: const Icon(
                        Icons.close,
                        color: Colors.grey,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
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
