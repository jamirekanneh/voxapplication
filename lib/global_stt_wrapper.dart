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
      await tts.togglePause(
        context.read<LanguageProvider>().currentLocale,
      );
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
      partialResults: true, // FIX: was false — ensures _lastWords is set before onStatus fires
    );
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
          ],
        ),
      ),
    );
  }
}