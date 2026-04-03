import 'package:flutter/material.dart';
import 'contact_us_page.dart';

const _kBgColor = Color(0xFFF3E5AB);
const _kHeaderColor = Color(0xFFD4B96A);
const _kNavy = Color(0xFF1A1A2E);

class AskQuestionsPage extends StatefulWidget {
  const AskQuestionsPage({super.key});

  @override
  State<AskQuestionsPage> createState() => _AskQuestionsPageState();
}

class _AskQuestionsPageState extends State<AskQuestionsPage> {
  final List<Map<String, String>> faqs = [
    {
      'q': 'How do I recover deleted files?',
      'a':
          'Open the main Menu and navigate to "Recycle Files". From there, you can view your deleted notes and files and safely restore them directly to your library.',
    },
    {
      'q': 'Is my data securely backed up?',
      'a':
          'Yes! If you are logged into an authenticated account, your files and notes are securely backed up to the cloud. If you are using Guest Mode, your data is temporary and only saves locally to your device during the session.',
    },
    {
      'q': 'How can I reach support?',
      'a':
          'You can reach out to our dedicated support team using the "Contact Us" page inside the main menu. We provide support through both WhatsApp and Email!',
    },
    {
      'q': 'Can I use Voice Commands?',
      'a':
          'Absolutely! Visit the Commands section in the Menu to view our rich library of voice commands. You can also customize them manually to better fit your workflow.',
    },
    {
      'q': 'How do voice commands work?',
      'a':
          'Voice commands use speech recognition to let you control the app hands-free. Double-tap anywhere on the screen to activate voice mode, then speak your command. The app recognizes phrases like "open notes", "play reading", or your custom commands.',
    },
    {
      'q': 'What are custom voice commands?',
      'a':
          'Custom commands let you create your own voice phrases that trigger specific actions. For example, you could create a command called "morning routine" that opens your notes, reads the latest entry, and starts text-to-speech playback - all with one voice command.',
    },
    {
      'q': 'How do macro sequences work?',
      'a':
          'Macro sequences allow you to chain multiple commands together. Create a custom command with the "Run Macro Sequence" action, then list your desired commands line by line (e.g., "open notes", "search notes for meeting", "play reading").',
    },
    {
      'q': 'How does file upload and OCR work?',
      'a':
          'Upload documents, images, or PDFs through the Upload page. The app uses Google ML Kit to extract text from images and documents via OCR (Optical Character Recognition). You can then read the extracted text or save it as notes.',
    },
    {
      'q': 'What file types can I upload?',
      'a':
          'You can upload images (JPG, PNG), PDFs, Word documents (DOCX), and other common document formats. The app validates file size (max 10MB) and type for security. OCR works best with clear, well-lit images.',
    },
    {
      'q': 'How does the AI assistant work?',
      'a':
          'The AI assistant uses Groq API to provide intelligent responses to your questions. You can ask about document content, get summaries, or request explanations. The AI analyzes your uploaded documents and notes to give contextual answers.',
    },
    {
      'q': 'What is text-to-speech (TTS)?',
      'a':
          'TTS converts written text into spoken audio. Use voice commands like "play reading" or "pause" to control playback. You can adjust speech rate with "speed up" or "slow down" commands. TTS works with notes, documents, and AI responses.',
    },
    {
      'q': 'How do I manage my notes and library?',
      'a':
          'Your notes are organized in the Library section. You can create new notes, edit existing ones, search by keywords, and categorize them. All notes sync to the cloud if you have an authenticated account.',
    },
    {
      'q': 'What languages does the app support?',
      'a':
          'The app supports multiple languages for voice commands and TTS: English, Spanish, French, Arabic, Turkish, and Chinese. Language preferences are saved per user account.',
    },
    {
      'q': 'How does the dictionary feature work?',
      'a':
          'The dictionary helps you look up word definitions and pronunciations. You can search for words using voice commands or text input. It\'s particularly useful when reading documents in foreign languages.',
    },
    {
      'q': 'What is the Statistics page?',
      'a':
          'The Statistics page shows usage analytics including reading time, voice commands used, files uploaded, and AI interactions. This data helps you track your productivity and app usage patterns.',
    },
    {
      'q': 'How does guest mode work?',
      'a':
          'Guest mode lets you try the app without creating an account. Your data is stored locally and temporarily. Create an account to save your notes, custom commands, and access cloud backup.',
    },
    {
      'q': 'Is my data private and secure?',
      'a':
          'Yes! We use Firebase security rules to ensure only you can access your own data. Files are validated for security, and sensitive information like API keys is properly protected. Guest mode data stays on your device only.',
    },
    {
      'q': 'How does speech-to-text work?',
      'a':
          'Speech-to-text converts your voice into written text. Use it to dictate notes, search queries, or voice commands. The app supports continuous listening and provides real-time transcription feedback.',
    },
    {
      'q': 'Can I use the app hands-free?',
      'a':
          'Yes! The app is designed for accessibility. Use voice commands for navigation, create macro sequences for complex tasks, and rely on TTS for reading content. Double-tap gestures activate voice mode throughout the app.',
    },
    {
      'q': 'How do I create custom commands?',
      'a':
          'Go to Menu → Voice Commands → Add Command. Choose a phrase to say, select an action (like opening notes or running a macro), and optionally add parameters. Your custom commands sync across devices with your account.',
    },
    {
      'q': 'What is the difference between guest and authenticated accounts?',
      'a':
          'Guest accounts store data locally and temporarily. Authenticated accounts provide cloud backup, cross-device sync, custom command persistence, and access to advanced features like detailed analytics.',
    },
  ];

  void _showChatBox(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SupportChatBot(faqs: faqs),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        title: const Text(
          'FAQs',
          style: TextStyle(fontWeight: FontWeight.bold, color: _kNavy),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: _kNavy),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _kNavy,
        onPressed: () => _showChatBox(context),
        child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Text(
                'Frequently Asked Questions',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _kNavy.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: faqs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _kNavy.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        iconColor: _kHeaderColor,
                        collapsedIconColor: _kNavy,
                        title: Text(
                          faqs[index]['q']!,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: _kNavy),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                faqs[index]['a']!,
                                style: TextStyle(
                                  color: Colors.black87.withValues(alpha: 0.8),
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const ContactUsPage()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kNavy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.mail_outline_rounded),
                label: const Text('Still have a question? Contact Us'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Chatbox Widget
class _SupportChatBot extends StatefulWidget {
  final List<Map<String, String>> faqs;
  const _SupportChatBot({required this.faqs});

  @override
  State<_SupportChatBot> createState() => _SupportChatBotState();
}

class _SupportChatBotState extends State<_SupportChatBot> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [
    {'text': 'Hi! I am your App Assistant. How can I help you today?', 'isUser': false},
  ];

  void _handleSend() {
    if (_controller.text.trim().isEmpty) return;

    final userQuery = _controller.text.trim();
    setState(() {
      _messages.add({'text': userQuery, 'isUser': true});
    });
    _controller.clear();

    // Enhanced Logic: Smart FAQ matching with keywords and synonyms
    String response = _findBestResponse(userQuery);

    // Add delay to simulate "thinking"
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _messages.add({'text': response, 'isUser': false});
        });
      }
    });
  }

  String _findBestResponse(String query) {
    final queryLower = query.toLowerCase().trim();

    // Define keyword mappings for better matching
    final keywordMappings = {
      // Voice commands
      'voice': ['voice', 'speak', 'talk', 'command', 'say', 'tell'],
      'custom': ['custom', 'personal', 'my own', 'create', 'make'],
      'macro': ['macro', 'sequence', 'chain', 'multiple', 'routine', 'workflow'],

      // File operations
      'upload': ['upload', 'file', 'document', 'pdf', 'image', 'scan'],
      'ocr': ['ocr', 'text recognition', 'extract', 'scan', 'read text'],
      'delete': ['delete', 'remove', 'trash', 'recycle', 'recover'],

      // AI features
      'ai': ['ai', 'assistant', 'groq', 'intelligent', 'smart', 'answer'],
      'tts': ['tts', 'speech', 'read aloud', 'speak', 'voice', 'audio'],

      // Account & data
      'account': ['account', 'login', 'user', 'profile', 'auth'],
      'guest': ['guest', 'temporary', 'local', 'no account'],
      'backup': ['backup', 'cloud', 'sync', 'save', 'store'],
      'security': ['security', 'private', 'safe', 'protect', 'secure'],

      // App features
      'note': ['note', 'notes', 'library', 'write', 'text'],
      'dictionary': ['dictionary', 'word', 'definition', 'meaning'],
      'statistics': ['statistics', 'analytics', 'stats', 'usage', 'track'],
      'language': ['language', 'lang', 'translate', 'multi'],

      // Accessibility
      'blind': ['blind', 'vision', 'sight', 'see', 'visual'],
      'hands': ['hands', 'free', 'touch', 'gesture', 'accessibility'],
      'speech': ['speech', 'talk', 'voice', 'speak', 'say'],
    };

    // Score each FAQ based on keyword matches
    Map<String, double> scores = {};

    for (var faq in widget.faqs) {
      double score = 0.0;
      final question = faq['q']!.toLowerCase();

      // Direct substring match (high weight)
      if (question.contains(queryLower) || queryLower.contains(question)) {
        score += 3.0;
      }

      // Keyword matching
      for (var keyword in keywordMappings.keys) {
        if (queryLower.contains(keyword)) {
          for (var synonym in keywordMappings[keyword]!) {
            if (question.contains(synonym)) {
              score += 1.0;
              break; // Only count once per keyword group
            }
          }
        }
      }

      // Word overlap scoring
      final queryWords = queryLower.split(RegExp(r'\s+'));
      final questionWords = question.split(RegExp(r'\s+'));

      int overlapCount = 0;
      for (var qWord in queryWords) {
        if (qWord.length > 2) { // Ignore very short words
          for (var aWord in questionWords) {
            if (aWord.contains(qWord) || qWord.contains(aWord)) {
              overlapCount++;
              break;
            }
          }
        }
      }

      if (queryWords.isNotEmpty) {
        score += (overlapCount / queryWords.length) * 2.0;
      }

      scores[faq['q']!] = score;
    }

    // Find the best match
    String? bestQuestion;
    double bestScore = 0.5; // Minimum threshold

    scores.forEach((question, score) {
      if (score > bestScore) {
        bestScore = score;
        bestQuestion = question;
      }
    });

    if (bestQuestion != null) {
      // Return the answer for the best matching question
      for (var faq in widget.faqs) {
        if (faq['q'] == bestQuestion) {
          return faq['a']!;
        }
      }
    }

    // Fallback responses based on query content
    if (queryLower.contains('help') || queryLower.contains('support')) {
      return 'I\'m here to help! You can ask me about voice commands, file uploads, AI features, security, or any other app functionality. Try questions like "How do voice commands work?" or "What files can I upload?"';
    }

    if (queryLower.contains('thank')) {
      return 'You\'re welcome! Feel free to ask me anything else about the app.';
    }

    if (queryLower.contains('hi') || queryLower.contains('hello')) {
      return 'Hello! I\'m your app assistant. I can help you understand how features work, answer questions about the app, or guide you through common tasks. What would you like to know?';
    }

    // Default fallback
    return "I'm sorry, I don't have a specific answer for that. You can try asking about voice commands, file uploads, AI features, security, or accessibility. For detailed support, visit the Contact Us page!";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            height: 5,
            width: 40,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
          ),
          const Text('App Assistant', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _kNavy)),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Align(
                  alignment: msg['isUser'] ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: msg['isUser'] ? _kNavy : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      msg['text'],
                      style: TextStyle(color: msg['isUser'] ? Colors.white : Colors.black87),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16, left: 16, right: 16, top: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Type a question...',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: _kNavy,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _handleSend,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}