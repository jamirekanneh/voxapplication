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
          'Open Menu → Recycle Bin. You can restore deleted notes, voice recordings, and uploaded library files. The Commands tab was removed—only Notes, Recordings, and Uploads are listed.',
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
      'q': 'Can I use voice commands while the app reads aloud?',
      'a':
          'Yes. Open any document and start read-aloud — the mic listens for pause, play, continue, stop, forward, and back. '
          'For the most reliable hands-free experience, use wired or Bluetooth earphones: TTS plays in your ears and the microphone hears only you, not the speaker. '
          'If voice control is missed or read-aloud sounds too quiet on the phone speaker alone, plug in earphones and try again. '
          'You can also tap pause on screen, then say continue or play to resume.',
    },
    {
      'q': 'How do voice commands work?',
      'a':
          'On Home, turn on Assistant for hands-free control, or double-tap anywhere when Assistant is enabled. Say phrases like "open notes", "open dictionary", or "open saved docs". Custom commands are in Menu. The search-bar mic on Home and Dictionary is separate—it filters your library or looks up words and temporarily pauses the Assistant.',
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
          'Open Dictionary from the bottom navigation. Choose General, Medical, or Technical sources. Type a word or tap the mic in the search bar to speak it. You can also say "open dictionary" or "define [word]" from Home when Assistant is on.',
    },
    {
      'q': 'What is the Statistics page?',
      'a':
          'Menu → Statistics shows reading time, voice usage, uploads, and AI activity. It includes gamification: XP, levels, achievements, weekly trends, and reading streaks. Data syncs to the cloud when you are signed in.',
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
          'Study Buddy is a chat that answers questions about text you are reading or a note transcript. Find it in the document reader AI tools, in a note\'s detail sheet (Summarize / Q&A / Study Buddy bar), and in the notes editor when a transcript is ready. It uses your actual document or transcript content.',
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
          'Guest mode keeps data on this device for the session. Signed-in accounts get cloud backup, Saved Docs, Statistics sync, custom command sync, and Reminders tied to your library and notes.',
    },
    {
      'q': 'What are Saved Docs?',
      'a':
          'Menu → Saved Docs stores AI summaries, Q&A sets from Home or Notes, and note transcripts you save. Search by title, open to read, export, or delete. Requires signing in (not guest mode).',
    },
    {
      'q': 'How do Reminders work?',
      'a':
          'Menu → Reminders lets you schedule a phone notification to study a specific library file or voice note. Pick the item, date, time, and whether it repeats daily. The old Remind button in the reader was moved here.',
    },
    {
      'q': 'How do I use voice search on Home?',
      'a':
          'On Home, tap the mic icon inside the library search bar (not the Assistant toggle). Speak your search words—they filter your uploaded files. While the search mic is active, the hands-free Assistant pauses so only one microphone session runs at a time.',
    },
    {
      'q': 'What is the floating chatbot on Menu and FAQs?',
      'a':
          'The blue "?" button opens the Vox Assistant chat. Ask how features work, navigation, or troubleshooting. You can type or use the mic in the chat sheet. It is for app help—not the same as Study Buddy, which answers about a specific document or note.',
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
