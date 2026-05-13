import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'contact_us_page.dart';
import 'floating_chat_bot.dart';
import 'theme_provider.dart';

class AskQuestionsPage extends StatefulWidget {
  const AskQuestionsPage({super.key});

  @override
  State<AskQuestionsPage> createState() => _AskQuestionsPageState();
}

class _AskQuestionsPageState extends State<AskQuestionsPage> {
  final FlutterTts _tts = FlutterTts();
  int _playingIndex = -1;

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
          'Macro sequences allow you to chain multiple commands together. Create a custom command with the "Run Macro Sequence" action, then list your desired commands line by line.',
    },
    {
      'q': 'How does file upload and OCR work?',
      'a':
          'Upload documents, images, or PDFs through the Upload page. The app uses Google ML Kit to extract text from images and documents via OCR. You can then read the extracted text or save it as notes.',
    },
    {
      'q': 'What file types can I upload?',
      'a':
          'You can upload images (JPG, PNG), PDFs, Word documents (DOCX), and other common document formats. The app validates file size (max 10MB) and type for security.',
    },
    {
      'q': 'How does the AI assistant work?',
      'a':
          'The AI assistant uses OpenRouter API to provide intelligent responses to your questions. You can ask about document content, get summaries, or request explanations.',
    },
    {
      'q': 'What is text-to-speech (TTS)?',
      'a':
          'TTS converts written text into spoken audio. Use voice commands like "play reading" or "pause" to control playback. You can adjust speech rate with "speed up" or "slow down" commands.',
    },
    {
      'q': 'How do I manage my notes and library?',
      'a':
          'Your notes are organized in the Library section. You can create new notes, edit existing ones, search by keywords, and categorize them. All notes sync to the cloud if you have an authenticated account.',
    },
    {
      'q': 'What languages does the app support?',
      'a':
          'The app supports multiple languages for voice commands and TTS: English, Spanish, French, Arabic, Turkish, and Chinese.',
    },
    {
      'q': 'How does the dictionary feature work?',
      'a':
          'The dictionary helps you look up word definitions and pronunciations. You can search for words using voice commands or text input.',
    },
    {
      'q': 'What is the Statistics page?',
      'a':
          'The Statistics page shows usage analytics including reading time, voice commands used, files uploaded, and AI interactions.',
    },
    {
      'q': 'How does guest mode work?',
      'a':
          'Guest mode lets you try the app without creating an account. Your data is stored locally and temporarily. Create an account to save your notes and access cloud backup.',
    },
    {
      'q': 'Is my data private and secure?',
      'a':
          'Yes! We use Firebase security rules to ensure only you can access your own data. Files are validated for security, and sensitive information like API keys is properly protected.',
    },
    {
      'q': 'How does speech-to-text work?',
      'a':
          'Speech-to-text converts your voice into written text. Use it to dictate notes, search queries, or voice commands. The app supports continuous listening and provides real-time transcription feedback.',
    },
    {
      'q': 'Can I use the app hands-free?',
      'a':
          'Yes! The app is designed for accessibility. Use voice commands for navigation, create macro sequences for complex tasks, and rely on TTS for reading content.',
    },
    {
      'q': 'How do I create custom commands?',
      'a':
          'Go to Menu → Voice Commands → Add Command. Choose a phrase to say, select an action, and optionally add parameters. Your custom commands sync across devices with your account.',
    },
    {
      'q': 'What is the AI Study Buddy?',
      'a':
          'The AI Study Buddy is an interactive chat inside the document reader. You can ask it questions about what you are currently reading or get explanations of complex paragraphs.',
    },
    {
      'q': 'How do I use OpenDyslexic font or Bionic Reading?',
      'a':
          'Open the document reader and tap the Settings gear in the top bar. You can toggle "OpenDyslexic Font" or "Bionic Reading" to bold the starts of words.',
    },
    {
      'q': 'What are Reading Streaks and Goals?',
      'a':
          'Streaks track how many consecutive days you have met your daily reading goal. You can set your daily target in the Statistics page.',
    },
    {
      'q': 'What is the difference between guest and authenticated accounts?',
      'a':
          'Guest accounts store data locally and temporarily. Authenticated accounts provide cloud backup, cross-device sync, custom command persistence, and access to advanced features.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _playingIndex = -1);
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _playFaq(int index) async {
    if (_playingIndex == index) {
      await _tts.stop();
      setState(() => _playingIndex = -1);
    } else {
      await _tts.stop();
      setState(() => _playingIndex = index);
      final fullText =
          "Question: ${faqs[index]['q']}. Answer: ${faqs[index]['a']}";
      await _tts.speak(fullText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = VoxColors.primary(context);
    final onBg = VoxColors.onBg(context);

    return FloatingBotWrapper(
      child: Scaffold(
        backgroundColor: VoxColors.bg(context),
        appBar: AppBar(
          title: Text(
            'FAQs',
            style: TextStyle(fontWeight: FontWeight.bold, color: onBg),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: onBg),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Text(
                  'Frequently Asked Questions',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: onBg,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  itemCount: faqs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return Container(
                      decoration: BoxDecoration(
                        color: VoxColors.cardFill(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: VoxColors.border(context)),
                      ),
                      child: Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          iconColor: primary,
                          collapsedIconColor: VoxColors.textSecondary(context),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  faqs[index]['q']!,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: onBg,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _playingIndex == index
                                      ? Icons.stop_circle
                                      : Icons.play_circle_fill,
                                  color: primary,
                                ),
                                onPressed: () => _playFaq(index),
                              ),
                            ],
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  faqs[index]['a']!,
                                  style: TextStyle(
                                    color: VoxColors.textSecondary(context),
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
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.mail_outline_rounded),
                  label: const Text('Still have a question? Contact Us'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
