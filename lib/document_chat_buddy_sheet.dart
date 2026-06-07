import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'ai_service.dart';
import 'language_provider.dart';
import 'services/groq_service.dart';
import 'services/mic_coordinator.dart';
import 'services/app_speech_service.dart';
import 'tts_service.dart';

/// Chat sheet for asking questions about a document or note transcript.
class DocumentChatBuddySheet extends StatefulWidget {
  final String documentTitle;
  final String documentContent;

  const DocumentChatBuddySheet({
    super.key,
    required this.documentTitle,
    required this.documentContent,
  });

  static Future<void> show(
    BuildContext context, {
    required String documentTitle,
    required String documentContent,
  }) {
    final cleaned = documentContent.trim();
    if (cleaned.isEmpty) return Future.value();
    if (GroqService.isTranscriptPending(cleaned)) {
      final lang = context.read<LanguageProvider>();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.t('transcript_not_ready_chat')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return Future.value();
    }

    MicCoordinator.instance.setChatbotSheetOpen(true);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DocumentChatBuddySheet(
        documentTitle: documentTitle,
        documentContent: cleaned,
      ),
    ).whenComplete(() {
      MicCoordinator.instance.setChatbotSheetOpen(false);
      MicCoordinator.instance.setChatbotListening(false);
    });
  }

  @override
  State<DocumentChatBuddySheet> createState() => _DocumentChatBuddySheetState();
}

class _DocumentChatBuddySheetState extends State<DocumentChatBuddySheet>
    with SingleTickerProviderStateMixin {
  static const _owner = 'study_buddy';

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _pulseController;

  bool _isListening = false;
  bool _isLoading = false;
  bool _voiceOutputEnabled = true;
  final List<Map<String, String>> _messages = [];

  Future<void> _releaseMic() async {
    if (AppSpeechService.instance.activeOwner == _owner) {
      await AppSpeechService.instance.stop();
    }
    if (mounted) setState(() => _isListening = false);
    MicCoordinator.instance.setChatbotListening(false);
  }

  @override
  void initState() {
    super.initState();
    MicCoordinator.instance.registerReleaseHandler(_releaseMic);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    MicCoordinator.instance.unregisterReleaseHandler(_releaseMic);
    MicCoordinator.instance.setChatbotListening(false);
    _pulseController.dispose();
    if (AppSpeechService.instance.activeOwner == _owner) {
      AppSpeechService.instance.stop();
    }
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _listen() async {
    if (!_isListening) {
      await MicCoordinator.instance.yieldFromAssistant();
      if (!MicCoordinator.instance.chatbotMayListen) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.read<LanguageProvider>().t('chatbot_mic_menu_faqs'),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final available = await AppSpeechService.instance.ensureInitialized(
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
      if (!mounted || !available) return;

      MicCoordinator.instance.unregisterReleaseHandler(_releaseMic);
      await MicCoordinator.instance.releaseAll();
      if (!mounted) return;
      MicCoordinator.instance.registerReleaseHandler(_releaseMic);
      MicCoordinator.instance.setChatbotListening(true);
      setState(() => _isListening = true);
      await AppSpeechService.instance.listen(
        owner: _owner,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
        ),
        onResult: (val) {
          if (!mounted) return;
          setState(() => _controller.text = val.recognizedWords);
          if (val.hasConfidenceRating &&
              val.confidence > 0 &&
              val.finalResult) {
            _sendMessage();
          }
        },
      );
    } else {
      await _releaseMic();
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    if (_isListening) {
      await _releaseMic();
    }

    final history = _messages
        .where((m) => (m['content'] ?? '').trim().isNotEmpty)
        .map((m) => {'role': m['role']!, 'content': m['content']!})
        .toList();

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final response = await AiService.askAboutDocument(
        documentText: widget.documentContent,
        documentTitle: widget.documentTitle,
        userMessage: text,
        conversationHistory: history,
      );
      if (!mounted) return;
      setState(() {
        _messages.add({'role': 'assistant', 'content': response});
        _isLoading = false;
      });
      _scrollToBottom();

      if (_voiceOutputEnabled) {
        final locale = context.read<LanguageProvider>().currentLocale;
        final tts = context.read<TtsService>();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            tts.speakBrief(response, locale);
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      final err = e.toString().replaceFirst('Exception: ', '').trim();
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': 'Sorry, I encountered an error: $err',
        });
        _isLoading = false;
      });
      _scrollToBottom();
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
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Color(0xFF0A0E1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(top: BorderSide(color: Color(0xFF4B9EFF), width: 2)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.psychology,
                    color: Color(0xFF4B9EFF),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lang.t('study_buddy'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          widget.documentTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _voiceOutputEnabled
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      color: _voiceOutputEnabled
                          ? const Color(0xFF4B9EFF)
                          : Colors.white54,
                    ),
                    onPressed: () {
                      setState(() => _voiceOutputEnabled = !_voiceOutputEnabled);
                      if (!_voiceOutputEnabled) {
                        context.read<TtsService>().stop();
                      }
                    },
                    tooltip: lang.t('toggle_voice_output'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () {
                      context.read<TtsService>().stop();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                itemCount: _messages.length + 1 + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Text(
                          lang.t('study_buddy_greeting'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    );
                  }

                  final msgIndex = index - 1;
                  if (msgIndex == _messages.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        lang.t('study_buddy_thinking'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    );
                  }

                  final msg = _messages[msgIndex];
                  final isUser = msg['role'] == 'user';
                  return Align(
                    alignment:
                        isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78,
                      ),
                      decoration: BoxDecoration(
                        color: isUser
                            ? const Color(0xFF4B9EFF).withValues(alpha: 0.1)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isUser
                              ? const Color(0xFF4B9EFF).withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Text(
                        msg['content'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Row(
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
                                    color: Colors.redAccent.withValues(
                                      alpha: 0.4 * _pulseController.value,
                                    ),
                                    blurRadius: 12 * _pulseController.value,
                                    spreadRadius: 8 * _pulseController.value,
                                  ),
                                ]
                              : [],
                        ),
                        child: CircleAvatar(
                          backgroundColor: _isListening
                              ? Colors.redAccent
                              : Colors.white.withValues(alpha: 0.05),
                          child: IconButton(
                            icon: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              color: _isListening
                                  ? Colors.white
                                  : const Color(0xFF4B9EFF),
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
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: lang.t('ask_about_document'),
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
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
                      onPressed: _isLoading ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
