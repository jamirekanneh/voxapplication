import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'custom_commands_provider.dart';
import 'command_dispatcher.dart';
import 'tts_service.dart';
import 'language_provider.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  GLOBAL STT WRAPPER
//  Wrap your MaterialApp child with this widget.
//  Double-tap anywhere â†’ starts listening â†’ matches commands.
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

    // Listen for assistant mode toggle
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomCommandsProvider>().addListener(_onProviderChange);
    });
  }

  void _onProviderChange() {
    if (!mounted) return;
    final assistantEnabled =
        context.read<CustomCommandsProvider>().assistantModeEnabled;
    if (assistantEnabled && !_isListening) {
      _startListening();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (e) {
        if (mounted) _updateListening(false);
        // Auto-restart if assistant mode is on and it's not a fatal error
        _checkAutoRestart();
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) _updateListening(false);
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

    // Force cancel any stuck session before starting
    await _speech.stop();
    await _speech.cancel();

    _updateListening(true);
    setState(() {
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
          true, // FIX: was false - ensures _lastWords is set before onStatus fires
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

    // If Assistant Mode is on, start listening again after a short delay
    _checkAutoRestart();
  }

  void _updateListening(bool value) {
    if (!mounted) return;
    setState(() => _isListening = value);
    context.read<CustomCommandsProvider>().setListening(value);
  }

  void _checkAutoRestart() {
    if (!mounted) return;
    final assistantEnabled =
        context.read<CustomCommandsProvider>().assistantModeEnabled;
    if (assistantEnabled && !_isListening) {
      // Short cooldown to allow the previous session to fully cleanup
      Future.delayed(const Duration(milliseconds: 500), () async {
        if (!mounted) return;
        final stillEnabled =
            context.read<CustomCommandsProvider>().assistantModeEnabled;
        if (stillEnabled && !_isListening) {
          // Re-initialize if it's been a while to keep the engine fresh
          await _initSpeech();
          if (mounted) _startListening();
        }
      });
    }
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
                            color: Color(0xFF0A0E1A).withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(40),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4B9EFF).withValues(alpha: 0.3),
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
                                color: Color(0xFF4B9EFF),
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Listeningâ€¦',
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

