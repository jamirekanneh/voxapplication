import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'custom_commands_provider.dart';
import 'command_dispatcher.dart';
import 'tts_service.dart';
import 'language_provider.dart';

// ─────────────────────────────────────────────
//  GLOBAL STT WRAPPER
//  Wrap your MaterialApp child with this widget.
//  Double-tap anywhere → starts listening → matches commands.
// ─────────────────────────────────────────────
class GlobalSttWrapper extends StatefulWidget {
  final Widget child;

  const GlobalSttWrapper({super.key, required this.child});

  @override
  State<GlobalSttWrapper> createState() => _GlobalSttWrapperState();
}

class _GlobalSttWrapperState extends State<GlobalSttWrapper>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;
  String _lastWords = '';

  bool _isChatOpen = false;
  final TextEditingController _chatTextController = TextEditingController();
  final List<Map<String, String>> _chatMessages = [];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initSpeech();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _chatTextController.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (e) {
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
          _handleResult();
        }
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _startListening() async {
    if (!_speechAvailable || _isListening) return;

    final tts = context.read<TtsService>();
    if (tts.isPlaying) {
      await tts.togglePause(context.read<LanguageProvider>().currentLocale);
    }

    setState(() {
      _isListening = true;
      _lastWords = '';
    });

    await _speech.listen(
      onResult: (result) {
        print('STT RESULT: "${result.recognizedWords}"'); // debug
        setState(() => _lastWords = result.recognizedWords);
      },
      localeId: context.read<LanguageProvider>().currentLocale,
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      partialResults:
          true, // FIX: was false — ensures _lastWords is set before onStatus fires
    );
  }

  Future<void> _toggleChat() async {
    setState(() => _isChatOpen = !_isChatOpen);
  }

  Future<void> _sendChatMessage() async {
    final text = _chatTextController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _chatMessages.add({'role': 'user', 'text': text});
      _chatTextController.clear();
    });

    final reply = _getChatbotResponse(text);
    await Future.delayed(const Duration(milliseconds: 200));

    if (!mounted) return;
    setState(() {
      _chatMessages.add({'role': 'bot', 'text': reply});
    });
  }

  String _getChatbotResponse(String query) {
    final q = query.toLowerCase();

    if (q.contains('help') || q.contains('how do i')) {
      return 'Hi there! This app has Home, Notes, Dictionary, Upload and Menu screens. Tap the bottom tabs to switch, or use the search field to look up words.';
    }

    if (q.contains('dictionary')) {
      return 'Open Dictionary and type a word. The app searches general, medical & technical entries, then shows definitions and audio.';
    }

    if (q.contains('notes')) {
      return 'Notes lets you create, edit and save personal notes. Use voice input command in the main area to quickly add content.';
    }

    if (q.contains('upload')) {
      return 'Upload screen lets you submit files or text with audio commands. It is also used for getting AI responses or saving content.';
    }

    if (q.contains('voice') || q.contains('command')) {
      return 'Double-tap anywhere to activate global voice command mode, then speak the command. Microphone permission is required.';
    }

    if (q.contains('app') || q.contains('feature')) {
      return 'The app includes editing, speech-to-text, text-to-speech, dictionary lookup, notes, profile and question-answer flow. Ask about any screen.';
    }

    return 'I am your assistant for VOX. Ask me about Dictionary, Notes, Upload, Menu, or how to use the app.';
  }

  Future<void> _handleResult() async {
    print('HANDLE RESULT: "$_lastWords"'); // debug
    if (_lastWords.isEmpty) return;
    if (!mounted) return;

    final commandsProvider = context.read<CustomCommandsProvider>();

    // FIX: don't match against an empty command list if provider hasn't loaded yet
    if (!commandsProvider.isLoaded) return;

    final ttsService = context.read<TtsService>();
    final langProvider = context.read<LanguageProvider>();

    await CommandDispatcher.dispatch(
      context: context,
      spokenText: _lastWords,
      commandsProvider: commandsProvider,
      ttsService: ttsService,
      langProvider: langProvider,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Double tap anywhere to activate voice commands',
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: _speechAvailable ? _startListening : null,
        child: Stack(
          children: [
            widget.child,

            if (_isChatOpen)
              Positioned(
                bottom: 88,
                right: 20,
                child: Container(
                  width: 300,
                  height: 360,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B4513),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'VOX Assistant',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() => _isChatOpen = false);
                              },
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: ListView(
                            reverse: true,
                            children: _chatMessages.reversed
                                .map(
                                  (entry) => Align(
                                    alignment: entry['role'] == 'user'
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: entry['role'] == 'user'
                                            ? const Color(0xFF8B4513)
                                            : const Color(0xFFFAF0E6),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        entry['text'] ?? '',
                                        style: TextStyle(
                                          color: entry['role'] == 'user'
                                              ? Colors.white
                                              : Colors.brown.shade900,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _chatTextController,
                                decoration: InputDecoration(
                                  hintText: 'Ask about the app...',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                ),
                                onSubmitted: (_) => _sendChatMessage(),
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: _sendChatMessage,
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B4513),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.send,
                                  color: Colors.white,
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
              ),

            if (_isListening)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: Semantics(
                    label: 'Listening for voice command',
                    liveRegion: true,
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (_, __) => Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.82),
                            borderRadius: BorderRadius.circular(40),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFD4B96A).withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.mic,
                                color: Color(0xFFD4B96A),
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Listening…',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            Positioned(
              bottom: 24,
              right: 20,
              child: GestureDetector(
                onTap: _toggleChat,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B4513), // brown
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _isChatOpen ? '×' : 'V',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
