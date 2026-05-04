import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
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
  bool _isHardwareListening = false;
  bool _showListeningUI = false;
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
    if (assistantEnabled && !_isHardwareListening) {
      _startListening(manual: false);
    } else if (!assistantEnabled && !_showListeningUI && _isHardwareListening) {
      // If toggled off while passively listening, stop hardware
      _speech.stop();
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
        if (mounted) _updateListening(hardware: false, ui: false);
        _checkAutoRestart();
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) _updateListening(hardware: false, ui: false);
          _handleResult();
        }
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _startListening({bool manual = false}) async {
    // Explicit permission check for robust Android support
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) return;

    if (!_speechAvailable || _isHardwareListening) return;

    final langProvider = context.read<LanguageProvider>();
    final tts = context.read<TtsService>();
    if (tts.isPlaying) {
      await tts.togglePause(langProvider.currentLocale);
    }

    // Force cancel any stuck session before starting
    await _speech.stop();
    await _speech.cancel();

    if (!mounted) return;

    _updateListening(hardware: true, ui: manual);
    setState(() {
      _lastWords = '';
    });

    await _speech.listen(
      onResult: (result) {
        debugPrint('STT RESULT: "${result.recognizedWords}"');
        if (mounted) setState(() => _lastWords = result.recognizedWords);
      },
      localeId: langProvider.currentLocale,
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
      ),
    );
  }

  Future<void> _handleResult() async {
    debugPrint('HANDLE RESULT: "$_lastWords"');
    String spokenText = _lastWords.toLowerCase().trim();
    if (spokenText.isEmpty) {
      _checkAutoRestart();
      return;
    }
    if (!mounted) return;

    bool hasWakeWord = false;
    final wakeWords = [
      'vox', 'hey vox', 'hello vox', 'ok vox', 'okay vox', 'hi vox', 
      'fox', 'hey fox', 'box', 'hey box', 'folks', 'hey folks', 
      'voks', 'volks', 'vocks', 'books', 'hey books', 'choice'
    ];
    
    // Check if the transcript contains any of our wake word variants
    for (final w in wakeWords) {
      if (spokenText.startsWith(w)) {
        hasWakeWord = true;
        spokenText = spokenText.substring(w.length).trim();
        debugPrint('MATCHED WAKE WORD (START): "$w"');
        break;
      } else if (spokenText.contains(w)) {
        hasWakeWord = true;
        final idx = spokenText.indexOf(w);
        spokenText = spokenText.substring(idx + w.length).trim();
        debugPrint('MATCHED WAKE WORD (CONTAINS): "$w"');
        break;
      }
    }

    final commandsProvider = context.read<CustomCommandsProvider>();
    if (!commandsProvider.isLoaded) return;

    // RE-ATTACH/INTENT-BASED WAKING: 
    // If the STT clipped the wake-word, we check if the command is a high-confidence local match.
    final matchedFailsafe = (spokenText == 'menu' || spokenText == 'notes' || 
                             spokenText == 'dictionary' || spokenText == 'home' ||
                             spokenText.contains('open menu') || spokenText.contains('go to menu') ||
                             spokenText.contains('profile') || spokenText.contains('language') ||
                             spokenText.contains('commands') || spokenText.contains('statistics') ||
                             spokenText.contains('about') || spokenText.contains('contact') ||
                             spokenText.contains('faq') || spokenText.contains('recommendation') ||
                             spokenText.contains('recycle bin') || spokenText.contains('history'));

    // Passive Wake Word Engine
    if (commandsProvider.assistantModeEnabled && !_showListeningUI) {
      if (!hasWakeWord && !matchedFailsafe) {
        debugPrint('PASSIVE MODE: Ignoring - no wake word or failsafe detected in "$spokenText"');
        _checkAutoRestart();
        return; 
      }
      
      if (spokenText.isEmpty && hasWakeWord) {
        // Said "Vox" and paused. Acknowledge and activate UI.
        debugPrint('WAKE WORD ONLY: Activating UI and acknowledging...');
        _updateListening(hardware: true, ui: true);
        
        if (commandsProvider.voiceFeedbackEnabled) {
          final ttsService = context.read<TtsService>();
          final locale = context.read<LanguageProvider>().currentLocale;
          ttsService.play('', 'Hey! I am listening.', locale);
        }
        
        _startListening(manual: true);
        return;
      }
      
      if (matchedFailsafe && !hasWakeWord) {
        debugPrint('PASSIVE MODE: Intent-based wake triggered by: "$spokenText"');
      }
    } else {
      // Active UI Engine
      if (spokenText.isEmpty) {
        debugPrint('ACTIVE MODE: Ignoring empty speech');
        _checkAutoRestart();
        return;
      }
    }

    final ttsService = context.read<TtsService>();
    final langProvider = context.read<LanguageProvider>();

    debugPrint('GLOBAL WRAPPER: Calling dispatch for "$spokenText"...');
    // UNBLOCK: Don't await the dispatch. Let it run in parallel so 
    // the STT engine can finish its cleanup and restart immediately.
    CommandDispatcher.dispatch(
      context: context,
      spokenText: spokenText,
      commandsProvider: commandsProvider,
      ttsService: ttsService,
      langProvider: langProvider,
    ).catchError((e, stack) {
      debugPrint('CRITICAL DISPATCH ERROR: $e');
      debugPrint(stack.toString());
      return false;
    });

    _checkAutoRestart();
  }

  void _updateListening({required bool hardware, required bool ui}) {
    if (!mounted) return;
    setState(() {
      _isHardwareListening = hardware;
      _showListeningUI = hardware && ui;
    });
    context.read<CustomCommandsProvider>().setListening(_showListeningUI);
  }

  void _checkAutoRestart() {
    if (!mounted) return;
    final assistantEnabled =
        context.read<CustomCommandsProvider>().assistantModeEnabled;
    if (assistantEnabled && !_isHardwareListening) {
      Future.delayed(const Duration(milliseconds: 500), () async {
        if (!mounted) return;
        final stillEnabled =
            context.read<CustomCommandsProvider>().assistantModeEnabled;
        if (stillEnabled && !_isHardwareListening) {
          await _initSpeech();
          if (mounted) _startListening(manual: false); // Auto restart hidden
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
        onDoubleTap: _speechAvailable ? () => _startListening(manual: true) : null,
        child: Stack(
          children: [
            widget.child,

            if (_showListeningUI)
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
                      builder: (context, _) => Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A0E1A).withOpacity(0.82),
                            borderRadius: BorderRadius.circular(40),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4B9EFF).withOpacity(0.3),
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
