import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'custom_commands_provider.dart';
import 'command_dispatcher.dart';
import 'services/assistant_voice_phrases.dart';
import 'tts_service.dart';
import 'language_provider.dart';
import 'services/mic_coordinator.dart';
import 'services/reading_voice_listener.dart';
import 'services/read_aloud_ui.dart';
import 'services/app_speech_service.dart';
import 'mini_player_bar.dart';

// ─────────────────────────────────────────────
//  GLOBAL STT WRAPPER
//  Wrap your MaterialApp child with this widget.
//  Double-tap anywhere → toggles Assistant on/off and listens when on.
// ─────────────────────────────────────────────
class GlobalSttWrapper extends StatefulWidget {
  final Widget child;

  const GlobalSttWrapper({super.key, required this.child});

  @override
  State<GlobalSttWrapper> createState() => _GlobalSttWrapperState();
}

class _GlobalSttWrapperState extends State<GlobalSttWrapper>
    with SingleTickerProviderStateMixin {
  static const _owner = 'assistant';

  bool _isHardwareListening = false;
  bool _showListeningUI = false;
  bool _speechAvailable = false;
  String _lastWords = '';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late ReadingVoiceListener _readingVoiceListener;

  Future<void> _releaseMicForRecording() async {
    _updateListening(hardware: false, ui: false);
    if (AppSpeechService.instance.activeOwner == _owner) {
      await AppSpeechService.instance.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    MicCoordinator.instance.requestAssistantListen = _activateAssistant;
    MicCoordinator.instance.registerReleaseHandler(_releaseMicForRecording);
    MicCoordinator.instance.addListener(_onMicPriorityChanged);
    _initSpeech();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _readingVoiceListener = ReadingVoiceListener(hostState: this);
    unawaited(_readingVoiceListener.init());

    // Listen for assistant mode toggle + read-aloud voice controls
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomCommandsProvider>().addListener(_onProviderChange);
      context.read<TtsService>().addListener(_onTtsChanged);
    });
  }

  void _onTtsChanged() {
    if (!mounted) return;
    _readingVoiceListener.onTtsChanged();
  }

  void _onMicPriorityChanged() {
    if (!mounted) return;
    _readingVoiceListener.onMicChanged();
    if (MicCoordinator.instance.authFlowActive) {
      if (_isHardwareListening) {
        unawaited(_releaseMicForRecording());
      }
      return;
    }
    if (MicCoordinator.instance.searchMicActive) return;

    // Read-aloud playing — assistant must yield; mini-player voice owns the mic.
    if (MicCoordinator.instance.readAloudBlocksOtherMics) {
      if (_isHardwareListening) {
        MicCoordinator.instance.setAssistantMicActive(false);
        unawaited(_releaseMicForRecording());
      }
      return;
    }

    final provider = context.read<CustomCommandsProvider>();
    if (MicCoordinator.instance.assistantMayListen &&
        provider.assistantModeEnabled &&
        !_isHardwareListening) {
      unawaited(_startListening(manual: true));
      return;
    }

    if (!MicCoordinator.instance.assistantMicActive && _isHardwareListening) {
      unawaited(_releaseMicForRecording());
    }
  }

  void _onProviderChange() {
    if (!mounted) return;
    if (MicCoordinator.instance.searchMicActive) return;
    final assistantEnabled =
        context.read<CustomCommandsProvider>().assistantModeEnabled;
    if (!assistantEnabled) {
      MicCoordinator.instance.setAssistantMicActive(false);
      if (_isHardwareListening) {
        unawaited(_releaseMicForRecording());
      }
    }
  }

  @override
  void dispose() {
    if (MicCoordinator.instance.requestAssistantListen == _activateAssistant) {
      MicCoordinator.instance.requestAssistantListen = null;
    }
    MicCoordinator.instance.removeListener(_onMicPriorityChanged);
    MicCoordinator.instance.unregisterReleaseHandler(_releaseMicForRecording);
    try {
      context.read<TtsService>().removeListener(_onTtsChanged);
    } catch (_) {}
    _readingVoiceListener.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _showAssistantToggleSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deactivateAssistant({bool manual = true}) async {
    if (!mounted) return;
    final provider = context.read<CustomCommandsProvider>();
    final lang = context.read<LanguageProvider>();

    await provider.setAssistantMode(false);
    MicCoordinator.instance.setAssistantMicActive(false);
    _updateListening(hardware: false, ui: false);
    if (AppSpeechService.instance.activeOwner == _owner) {
      await AppSpeechService.instance.stop();
    }

    if (!manual || !mounted) return;
    _showAssistantToggleSnack(lang.t('assistant_off'));
    if (provider.voiceFeedbackEnabled) {
      context.read<TtsService>().speakBrief(
            lang.t('assistant_off'),
            lang.ttsLocale,
          );
    }
  }

  Future<void> _activateAssistant({bool manual = true}) async {
    if (!MicCoordinator.instance.assistantMayActivate) {
      if (manual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Assistant is unavailable while the document is playing. '
              'Pause from the mini player first, or use earphones and voice commands.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    if (!_speechAvailable) return;
    final provider = context.read<CustomCommandsProvider>();
    final lang = context.read<LanguageProvider>();

    // Double-tap toggles: first tap on → second tap off.
    if (manual && provider.assistantModeEnabled) {
      await _deactivateAssistant(manual: manual);
      return;
    }

    await provider.setAssistantMode(true);
    MicCoordinator.instance.setAssistantMicActive(true);
    await _startListening(manual: manual);

    if (manual && mounted) {
      _showAssistantToggleSnack(lang.t('assistant_on'));
    }
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await AppSpeechService.instance.ensureInitialized(
      owner: _owner,
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
    if (!MicCoordinator.instance.assistantMayListen) {
      if (manual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Assistant microphone is busy.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Explicit permission check for robust Android support
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) return;

    if (!_speechAvailable) return;
    if (_isHardwareListening &&
        AppSpeechService.instance.activeOwner == _owner) {
      await AppSpeechService.instance.stop();
      if (mounted) _updateListening(hardware: false, ui: false);
    }

    if (!mounted) return;

    final langProvider = context.read<LanguageProvider>();

    _updateListening(hardware: true, ui: manual);
    setState(() {
      _lastWords = '';
    });

    MicCoordinator.instance.unregisterReleaseHandler(_releaseMicForRecording);
    await MicCoordinator.instance.releaseAll(
      keepReadingVoice: MicCoordinator.instance.globalReadingVoiceActive,
    );
    if (!mounted) return;
    MicCoordinator.instance.registerReleaseHandler(_releaseMicForRecording);

    final started = await AppSpeechService.instance.handoffListen(
      owner: _owner,
      onResult: (result) {
        debugPrint('STT RESULT: "${result.recognizedWords}"');
        if (mounted) setState(() => _lastWords = result.recognizedWords);
      },
      localeId: langProvider.sttLocale,
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
      ),
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) _updateListening(hardware: false, ui: false);
          _handleResult();
        }
      },
      onError: (e) {
        if (mounted) _updateListening(hardware: false, ui: false);
        _checkAutoRestart();
      },
    );
    if (!started && mounted) {
      _updateListening(hardware: false, ui: false);
    }
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
    if (!commandsProvider.isLoaded) {
      _checkAutoRestart();
      return;
    }

    final assistantOn = commandsProvider.assistantModeEnabled;

    // Wake word only (e.g. "Hey Vox") — prompt and keep listening.
    if (spokenText.isEmpty && hasWakeWord) {
      debugPrint('WAKE WORD ONLY: Activating UI and acknowledging...');
      _updateListening(hardware: true, ui: true);
      if (commandsProvider.voiceFeedbackEnabled) {
        final ttsService = context.read<TtsService>();
        final locale = context.read<LanguageProvider>().currentLocale;
        final lang = context.read<LanguageProvider>().selectedLanguage;
        ttsService.speakBrief(
          AssistantVoicePhrases.listeningAck(lang),
          locale,
        );
      }
      _startListening(manual: true);
      return;
    }

    // Assistant off and not manually activated (double-tap) — ignore.
    if (!assistantOn && !_showListeningUI) {
      debugPrint('IGNORE: Assistant off and no manual listen UI');
      _checkAutoRestart();
      return;
    }

    if (spokenText.isEmpty) {
      debugPrint('IGNORE: Empty speech');
      _checkAutoRestart();
      return;
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
    final showAssistantUi =
        hardware && ui && MicCoordinator.instance.assistantMicActive;
    setState(() {
      _isHardwareListening = hardware;
      _showListeningUI = showAssistantUi;
    });
    context.read<CustomCommandsProvider>().setListening(showAssistantUi);
  }

  void _checkAutoRestart() {
    if (!mounted) return;
    if (MicCoordinator.instance.authFlowActive) return;
    if (MicCoordinator.instance.searchMicActive) return;
    if (MicCoordinator.instance.readAloudBlocksOtherMics) return;
    if (!MicCoordinator.instance.assistantMayListen) return;
    if (!MicCoordinator.instance.assistantMicActive) return;
    final assistantEnabled =
        context.read<CustomCommandsProvider>().assistantModeEnabled;
    if (assistantEnabled && !_isHardwareListening) {
      Future.delayed(const Duration(milliseconds: 500), () async {
        if (!mounted) return;
        if (MicCoordinator.instance.assistantMicActive &&
            MicCoordinator.instance.assistantMayListen &&
            !_isHardwareListening) {
          await _initSpeech();
          if (mounted) _startListening(manual: true);
        }
      });
    }
  }

  /// Bottom offset so the mini player clears the tab bar + center-docked upload FAB.
  double _miniPlayerBottomInset(BuildContext context) {
    final name = MicCoordinator.instance.currentRoute;
    const routesWithDockedFab = {
      '/home',
      '/notes',
      '/dictionary',
      '/menu',
    };
    if (name != null && routesWithDockedFab.contains(name)) {
      // BottomAppBar (65) + half the center-docked FAB + small gap.
      const barHeight = 65.0;
      const fabSize = 56.0;
      const gap = 10.0;
      return barHeight + (fabSize * 0.5) + gap;
    }
    return 12;
  }

  double _voiceTipBottom(TtsService tts, double miniPlayerBottom) {
    if (tts.showGlobalMiniPlayer) {
      return miniPlayerBottom + 76;
    }
    if (tts.suppressGlobalMiniPlayer) {
      return 150;
    }
    return 96;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MicCoordinator.instance,
      builder: (context, _) {
        return _buildWithTts(context);
      },
    );
  }

  Widget _buildWithTts(BuildContext context) {
    final tts = context.watch<TtsService>();
    final miniPlayerBottom = _miniPlayerBottomInset(context);
    final listeningBottom = tts.showGlobalMiniPlayer
        ? miniPlayerBottom + 72.0
        : 100.0;

    return Semantics(
      label: 'Double tap anywhere to turn Assistant on or off',
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: _speechAvailable ? () => _activateAssistant(manual: true) : null,
        child: Stack(
          children: [
            widget.child,

            if (tts.showGlobalMiniPlayer)
              Positioned(
                left: 8,
                right: 8,
                bottom: miniPlayerBottom,
                child: SafeArea(
                  top: false,
                  child: const MiniPlayerBar(),
                ),
              ),

            if (_showListeningUI &&
                MicCoordinator.instance.assistantMicActive)
              Positioned(
                bottom: listeningBottom,
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

            ValueListenableBuilder<bool>(
              valueListenable: ReadAloudUi.voiceTipVisible,
              builder: (context, visible, _) {
                if (!visible) return const SizedBox.shrink();
                return ValueListenableBuilder<String>(
                  valueListenable: ReadAloudUi.voiceTipMessage,
                  builder: (context, message, _) {
                    return ReadingVoiceTipBanner(
                      bottom: _voiceTipBottom(tts, miniPlayerBottom),
                      message: message,
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
