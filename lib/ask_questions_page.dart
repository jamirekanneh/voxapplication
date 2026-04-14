import 'package:flutter/material.dart';
import 'contact_us_page.dart';
import 'floating_chat_bot.dart';

const _kBgColor = Color(0xFFF0F4FF);
const _kHeaderColor = Color(0xFF4B9EFF);
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

  @override
  Widget build(BuildContext context) {
    return FloatingBotWrapper(
      child: Scaffold(
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
                                  color: Color(0xDD0A0E1A).withValues(alpha: 0.8),
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
    ));
  }
}

