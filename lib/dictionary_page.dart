import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/services.dart';

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
    tts.setLanguage("en-US");
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
      setState(() {
        meanings = ["Error loading definition"];
      });
    }

    setState(() => isLoading = false);
  }

  Future<void> speak(String text) async {
    await tts.speak(text);
  }

  Future<void> listen() async {
    if (!isListening) {
      bool available = await speech.initialize();
      if (available) {
        setState(() => isListening = true);
        speech.listen(
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
    setState(() {
      favorites.contains(w) ? favorites.remove(w) : favorites.add(w);
    });
  }

  Widget buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(30),
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
            icon: const Icon(Icons.search),
            onPressed: () => searchWord(controller.text),
          ),
          IconButton(
            icon: Icon(isListening ? Icons.mic : Icons.mic_none),
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
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 97, 97, 97),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Definition",
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  word,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.volume_up, color: Colors.white),
                onPressed: () => speak(word),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.white),
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
                  color: Colors.white,
                ),
                onPressed: () => toggleFavorite(word),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            partOfSpeech,
            style: const TextStyle(fontSize: 18, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: meanings.map((m) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(m, style: const TextStyle(color: Colors.white)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 243, 229, 171),
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 243, 229, 171),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Dictionary",
          style: TextStyle(
            color: Colors.black,
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.black),
            onPressed: () {
              Navigator.push(
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
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          buildSearchBar(),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          buildResultCard(),
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
      appBar: AppBar(
        title: const Text(
          "Search History",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: history.isEmpty
          ? const Center(child: Text("No history yet"))
          : ListView.builder(
              itemCount: history.length,
              itemBuilder: (context, index) {
                var item = history[index];
                DateTime time = item["time"];

                return Column(
                  children: [
                    ListTile(
                      title: Text(item["word"]),
                      subtitle: Text(formatDate(time)),
                      onTap: () {
                        onSelect(item["word"]);
                        Navigator.pop(context);
                      },
                    ),
                    const Divider(height: 1),
                  ],
                );
              },
            ),
    );
  }
}
