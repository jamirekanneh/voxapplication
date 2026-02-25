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

  @override
  void initState() {
    super.initState();
    _initTTS();
  }

  void _initTTS() {
    _tts.setLanguage("en-US");
    _tts.setPitch(1.0);
    _tts.setSpeechRate(0.5); // Adjust speed for better clarity
  }

  // VOICE COMMAND
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
              _processVoiceCommand(targetFile);
            }
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _processVoiceCommand(String fileName) {
    _showFloatingMessage(context, "Voice Command: Opening $fileName");
    _startReading("Opening $fileName and starting automated reading now.");
  }

  Future<void> _startReading(String text) async {
    await _tts.stop(); // Stop any current speech before starting new
    await _tts.speak(text);
  }

  void _showFloatingMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF333333),
        margin: const EdgeInsets.only(bottom: 110, left: 20, right: 20),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String userEmail =
        FirebaseAuth.instance.currentUser?.email ?? "demo@user.com";

    return Scaffold(
      // KEPT ORIGINAL BACKGROUND COLOR
      backgroundColor: const Color.fromARGB(255, 243, 229, 171),
      resizeToAvoidBottomInset: false,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // TOP BAR
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
                      onChanged: (value) =>
                          setState(() => _searchQuery = value.toLowerCase()),
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

              const SizedBox(height: 15),

              // FILE GRID
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('library')
                      .where('userId', isEqualTo: userEmail)
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

                    return GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3, // Smaller icons
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.9,
                          ),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        var data = docs[index].data() as Map<String, dynamic>;
                        String name = data['fileName'] ?? 'File';

                        return GestureDetector(
                          onTap: () => _startReading("Reading $name"),
                          child: _buildSmallFileCard(
                            name,
                            data['fileType'] ?? 'pdf',
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),

      // BOTTOM NAVIGATION
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 65,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(Icons.home, "Home", const Color(0xFF70E1C1)),

              _navItem(
                _isListening ? Icons.graphic_eq : Icons.mic,
                "Command",
                _isListening ? Colors.red : Colors.grey,
                onTap: _listen,
              ),

              const SizedBox(width: 48),

              _navItem(
                Icons.book,
                "Dictionary",
                Colors.grey,
                onTap: () {
                  Navigator.pushNamed(context, '/dictionary');
                },
              ),

              _navItem(Icons.menu, "Menu", Colors.grey),
            ],
          ),
        ),
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        // Match the background or keep a clean look
        backgroundColor: const Color(0xFF70E1C1),
        onPressed: () {
          Navigator.pushNamed(context, '/upload');
        },
        child: const Icon(Icons.file_upload_outlined, color: Color(0xFF1D3D3D)),
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

  // UPDATED FILE CARD: Smaller, Grey Color, and better layout
  Widget _buildSmallFileCard(String title, String type) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE0E0E0), // NEUTRAL GREY COLOR
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            type.contains('pdf') ? Icons.picture_as_pdf : Icons.description,
            color: Colors.grey[700], // Darker grey for the icon
            size: 24,
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
