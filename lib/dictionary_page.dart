import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:provider/provider.dart';
import 'language_provider.dart';

class DictionaryPage extends StatefulWidget {
  const DictionaryPage({super.key});

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  final TextEditingController controller = TextEditingController();
  final FlutterTts tts = FlutterTts();
  final stt.SpeechToText speech = stt.SpeechToText();

  bool isListening = false;
  bool isLoading = false;

  String word = "";
  String partOfSpeech = "";
  List<String> meanings = [];
  List<Map<String, dynamic>> history = [];
  List<String> favorites = [];

  @override
  void initState() {
    super.initState();
    _initTTS();
  }

  void _initTTS() {
    final langProvider = context.read<LanguageProvider>();
    tts.setLanguage(langProvider.ttsLocale);
    tts.setPitch(1.0);
  }

  Future<void> searchWord(String query) async {
    query = query.toLowerCase().replaceAll(RegExp(r'[^a-z]'), "");
    if (query.isEmpty) return;
    setState(() => isLoading = true);
    try {
      final url = "https://api.dictionaryapi.dev/api/v2/entries/en/$query";
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        meanings.clear();
        var defs = data[0]['meanings'][0]['definitions'];
        for (var d in defs) {
          meanings.add(d['definition']);
        }
        setState(() {
          word = data[0]['word'];
          partOfSpeech = data[0]['meanings'][0]['partOfSpeech'];
          history.removeWhere((e) => e["word"] == word);
          history.insert(0, {"word": word, "time": DateTime.now()});
        });
      } else {
        setState(() {
          word = query;
          partOfSpeech = "";
          meanings = ["No definition found"];
        });
      }
    } catch (e) {
      setState(() => meanings = ["Error loading definition"]);
    }
    setState(() => isLoading = false);
  }

  Future<void> speak(String text) async {
    // Always use current language for TTS
    final langProvider = context.read<LanguageProvider>();
    await tts.setLanguage(langProvider.ttsLocale);
    await tts.speak(text);
  }

  Future<void> listen() async {
    final langProvider = context.read<LanguageProvider>();
    if (!isListening) {
      bool available = await speech.initialize();
      if (available) {
        setState(() => isListening = true);
        speech.listen(
          localeId: langProvider.sttLocale,
          onResult: (result) {
            String spoken = result.recognizedWords;
            controller.text = spoken;
            searchWord(spoken);
          },
        );
      }
    } else {
      setState(() => isListening = false);
      speech.stop();
    }
  }

  void toggleFavorite(String w) {
    setState(
      () => favorites.contains(w) ? favorites.remove(w) : favorites.add(w),
    );
  }

  Widget buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: searchWord,
              decoration: const InputDecoration(
                hintText: "Search word...",
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black87),
            onPressed: () => searchWord(controller.text),
          ),
          IconButton(
            icon: Icon(
              isListening ? Icons.mic : Icons.mic_none,
              color: isListening ? Colors.red : Colors.black87,
            ),
            onPressed: listen,
          ),
        ],
      ),
    );
  }

  Widget buildResultCard() {
    if (word.isEmpty) return const SizedBox();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Definition",
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  word,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.volume_up, color: Colors.black54),
                onPressed: () => speak(word),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.black54),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: meanings.join("\n")));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Copied to clipboard")),
                  );
                },
              ),
              IconButton(
                icon: Icon(
                  favorites.contains(word)
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  color: Colors.black54,
                ),
                onPressed: () => toggleFavorite(word),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            partOfSpeech,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: meanings
                .map(
                  (m) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      m,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = context.watch<LanguageProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          "Dictionary",
          style: TextStyle(
            color: Colors.black,
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          // Current language badge
          Padding(
            padding: const EdgeInsets.only(right: 8),
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
          IconButton(
            icon: const Icon(Icons.history, color: Colors.black),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HistoryScreen(
                  history: history,
                  onSelect: (selectedWord) {
                    controller.text = selectedWord;
                    searchWord(selectedWord);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          buildSearchBar(),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(color: Colors.black),
            ),
          buildResultCard(),
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
              _navItem(
                Icons.note_alt_outlined,
                "Notes",
                Colors.grey[400]!,
                onTap: () => Navigator.pushReplacementNamed(context, '/notes'),
              ),
              const SizedBox(width: 48),
              _navItem(Icons.book, "Dictionary", Colors.white),
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

class HistoryScreen extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final Function(String) onSelect;

  const HistoryScreen({
    super.key,
    required this.history,
    required this.onSelect,
  });

  String formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;
    if (difference == 0) return "Today";
    if (difference == 1) return "Yesterday";
    return "${date.day}/${date.month}/${date.year}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          "Search History",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: history.isEmpty
          ? const Center(
              child: Text(
                "No history yet",
                style: TextStyle(color: Colors.black54),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: history.length,
              itemBuilder: (context, index) {
                var item = history[index];
                DateTime time = item["time"];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    title: Text(
                      item["word"],
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      formatDate(time),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.black45,
                    ),
                    onTap: () {
                      onSelect(item["word"]);
                      Navigator.pop(context);
                    },
                  ),
                );
              },
            ),
    );
  }
}
