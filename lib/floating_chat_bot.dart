import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'ai_service.dart';
import 'tts_service.dart';
import 'language_provider.dart';
import 'services/mic_coordinator.dart';
import 'services/app_speech_service.dart';
import 'services/document_language_service.dart';
import 'theme_provider.dart';

class FloatingBotWrapper extends StatefulWidget {
  final Widget child;

  const FloatingBotWrapper({super.key, required this.child});

  @override
  State<FloatingBotWrapper> createState() => _FloatingBotWrapperState();
}

class _FloatingBotWrapperState extends State<FloatingBotWrapper> {
  Offset position = const Offset(0, 100);
  bool isLeft = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = MediaQuery.of(context).size;
      setState(() {
        position = Offset(size.width - 60, size.height / 2);
        isLeft = false;
      });
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      position += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    final size = MediaQuery.of(context).size;
    final isLeftSide = position.dx + 30 < (size.width / 2); // 30 is half width

    setState(() {
      isLeft = isLeftSide;
      final targetX = isLeftSide ? 0.0 : size.width - 60.0;
      // Keep Y within screen bounds
      final targetY = position.dy.clamp(0.0, size.height - 60.0);
      position = Offset(targetX, targetY);
    });
  }

  void _openChat() {
    final ctx = context;
    MicCoordinator.instance.setChatbotSheetOpen(true);
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ChatBotBottomSheet(),
    ).whenComplete(() {
      MicCoordinator.instance.setChatbotSheetOpen(false);
      MicCoordinator.instance.setChatbotListening(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: position.dx,
          top: position.dy,
          child: GestureDetector(
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onTap: _openChat,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A2E5E), Color(0xFF0A0E1A)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4B9EFF).withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: const Color(0xFF4B9EFF).withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glow ring
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF4B9EFF).withValues(alpha: 0.1),
                        ),
                      ),
                      // Question mark
                      const Text(
                        '?',
                        style: TextStyle(
                          color: Color(0xFF4B9EFF),
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ChatBotBottomSheet extends StatefulWidget {
  const ChatBotBottomSheet({super.key});

  @override
  State<ChatBotBottomSheet> createState() => _ChatBotBottomSheetState();
}

class _ChatBotBottomSheetState extends State<ChatBotBottomSheet> with SingleTickerProviderStateMixin {
  static const _owner = 'chatbot';

  final TextEditingController _controller = TextEditingController();
  late AnimationController _pulseController;
  bool _isListening = false;
  final List<Map<String, String>> _messages = [
    {
      'role': 'assistant',
      'content': 'Hello! I am the Vox Assistant. How can I help you today?',
    },
  ];
  bool _isLoading = false;
  bool _voiceOutputEnabled = true;

  Future<void> _releaseChatbotMic() async {
    if (AppSpeechService.instance.activeOwner == _owner) {
      await AppSpeechService.instance.stop();
    }
    if (mounted) setState(() => _isListening = false);
    MicCoordinator.instance.setChatbotListening(false);
  }

  @override
  void initState() {
    super.initState();
    MicCoordinator.instance.registerReleaseHandler(_releaseChatbotMic);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    MicCoordinator.instance.unregisterReleaseHandler(_releaseChatbotMic);
    MicCoordinator.instance.setChatbotListening(false);
    _pulseController.dispose();
    if (AppSpeechService.instance.activeOwner == _owner) {
      AppSpeechService.instance.stop();
    }
    _controller.dispose();
    super.dispose();
  }

  void _listen() async {
    if (!_isListening) {
      await MicCoordinator.instance.yieldFromAssistant();
      if (!MicCoordinator.instance.chatbotMayListen) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.read<LanguageProvider>().t('chatbot_mic_menu_faqs'),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      bool available = await AppSpeechService.instance.ensureInitialized(
        owner: _owner,
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speech error: ${error.errorMsg}')),
          );
        },
      );
      if (!mounted) return;
      if (available) {
        MicCoordinator.instance.unregisterReleaseHandler(_releaseChatbotMic);
        await MicCoordinator.instance.releaseAll();
        if (!mounted) return;
        MicCoordinator.instance.registerReleaseHandler(_releaseChatbotMic);
        MicCoordinator.instance.setChatbotListening(true);
        setState(() => _isListening = true);
        final sttLocale = context.read<LanguageProvider>().sttLocale;
        await AppSpeechService.instance.listen(
          owner: _owner,
          localeId: sttLocale,
          listenOptions: stt.SpeechListenOptions(
            partialResults: true,
            listenMode: stt.ListenMode.dictation,
          ),
          onResult: (val) {
            if (!mounted) return;
            setState(() {
              _controller.text = val.recognizedWords;
            });
            if (val.hasConfidenceRating &&
                val.confidence > 0 &&
                val.finalResult) {
              _sendMessage(); // Auto-send when final
            }
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.read<LanguageProvider>().t('speech_not_available'),
            ),
          ),
        );
      }
    } else {
      await _releaseChatbotMic();
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final appLang = context.read<LanguageProvider>().selectedLanguage;
    final responseLang = DocumentLanguageService.detectSpokenLanguageName(
      text,
      fallback: appLang,
    );

    if (_isListening) {
      await _releaseChatbotMic();
    }

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isLoading = true;
    });
    _controller.clear();

    try {
      final response = await AiService.askAssistant(
        text,
        fallbackLanguage: appLang,
      );
      if (mounted) {
        setState(() {
          _messages.add({'role': 'assistant', 'content': response});
          _isLoading = false;
        });
        
        if (_voiceOutputEnabled) {
          final tts = context.read<TtsService>();
          final speakLocale = DocumentLanguageService.detectTtsLocale(
            response,
            fallbackLanguage: responseLang,
          );
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              tts.speakBrief(response, speakLocale);
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        final err = e.toString().replaceFirst('Exception: ', '').trim();
        setState(() {
          _messages.add({
            'role': 'assistant',
            'content': 'Sorry, I encountered an error: $err',
          });
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () =>
          MicCoordinator.instance.activateAssistant(manual: true),
      child: Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: VoxColors.bg(context),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  lang.t('vox_assistant'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: VoxColors.onBg(context),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _voiceOutputEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                        color: _voiceOutputEnabled
                            ? VoxColors.primary(context)
                            : VoxColors.textSecondary(context),
                      ),
                      onPressed: () {
                        setState(() {
                          _voiceOutputEnabled = !_voiceOutputEnabled;
                        });
                        if (!_voiceOutputEnabled) {
                          context.read<TtsService>().stop();
                        }
                      },
                      tooltip: lang.t('toggle_voice_output'),
                    ),
                    Consumer<TtsService>(
                      builder: (context, tts, _) {
                        if (tts.isPlaying && tts.title == 'Assistant') {
                          return IconButton(
                            icon: const Icon(Icons.stop_circle_rounded, color: Colors.redAccent),
                            onPressed: () => tts.stop(),
                            tooltip: lang.t('stop_voice_output'),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: VoxColors.textSecondary(context),
                      ),
                      onPressed: () {
                        context.read<TtsService>().stop();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ],
            ),
            Divider(color: VoxColors.border(context)),
            Expanded(
              child: ListView.builder(
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isUser = msg['role'] == 'user';
                  final isGreeting =
                      !isUser && index == 0 && _messages.length == 1;
                  final text = isGreeting
                      ? lang.t('chatbot_greeting')
                      : (msg['content'] ?? '');
                  return Align(
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isUser
                            ? VoxColors.primary(context).withValues(alpha: 0.1)
                            : VoxColors.cardFill(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isUser
                              ? VoxColors.primary(context).withValues(alpha: 0.3)
                              : VoxColors.border(context),
                        ),
                      ),
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 15,
                          color: VoxColors.onBg(context),
                          height: 1.4,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(),
              ),
            Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: _isListening
                            ? [
                                BoxShadow(
                                  color: Colors.redAccent.withValues(alpha: 0.4 * _pulseController.value),
                                  blurRadius: 12 * _pulseController.value,
                                  spreadRadius: 8 * _pulseController.value,
                                )
                              ]
                            : [],
                      ),
                      child: CircleAvatar(
                        backgroundColor: _isListening
                            ? Colors.redAccent
                            : VoxColors.cardFill(context),
                        child: IconButton(
                          icon: Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            color: _isListening
                                ? Colors.white
                                : VoxColors.primary(context),
                          ),
                          onPressed: _listen,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: VoxColors.onBg(context)),
                    decoration: InputDecoration(
                      hintText: lang.t('ask_something'),
                      hintStyle: TextStyle(color: VoxColors.textHint(context)),
                      filled: true,
                      fillColor: VoxColors.cardFill(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xFF4B9EFF),
                  child: IconButton(
                    icon: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }
}

