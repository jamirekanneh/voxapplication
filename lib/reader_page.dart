import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'tts_service.dart';
import 'language_provider.dart';

class ReaderPage extends StatefulWidget {
  final String title;
  final String content;
  final String locale;

  const ReaderPage({
    super.key,
    required this.title,
    required this.content,
    required this.locale,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _autoSpeed = false;
  bool _showSpeedPanel = false;
  bool _isListening = false;
  String _lastCommand = '';
  bool _voiceCommandReady = false;

  static const List<double> _speedPresets = [0.8, 1.0, 1.2, 1.5, 1.75, 2.0];

  // ── Voice command keywords ───────────────────────────
  static const Map<String, List<String>> _commands = {
    'pause': ['pause', 'stop reading', 'hold on', 'wait'],
    'play': ['play', 'resume', 'continue', 'start', 'go'],
    'faster': ['faster', 'speed up', 'increase speed', 'fast'],
    'slower': ['slower', 'slow down', 'decrease speed', 'slow'],
    'forward': ['forward', 'skip', 'next', 'ahead', 'skip forward'],
    'backward': ['back', 'backward', 'rewind', 'go back', 'previous'],
    'restart': ['restart', 'from the beginning', 'start over'],
    'stop': ['stop', 'close', 'exit reader', 'quit'],
  };

  @override
  void initState() {
    super.initState();
    final tts = context.read<TtsService>();
    if (!tts.isPlaying || tts.title != widget.title) {
      tts.play(widget.title, widget.content, widget.locale);
    }
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      final available = await _speech.initialize(
        onError: (_) => setState(() => _isListening = false),
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
      );
      if (mounted) setState(() => _voiceCommandReady = available);
    }
  }

  Future<void> _toggleVoiceCommand() async {
    final tts = context.read<TtsService>();
    final locale = context.read<LanguageProvider>().ttsLocale;

    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      // Resume TTS if it was paused for listening
      if (!tts.isPlaying && tts.content != null) {
        await tts.togglePause(locale);
      }
      return;
    }

    // Pause TTS while listening so mic picks up clearly
    if (tts.isPlaying) await tts.togglePause(locale);

    setState(() {
      _isListening = true;
      _lastCommand = 'Listening...';
    });

    await _speech.listen(
      localeId: 'en_US', // commands always in English
      onResult: (result) {
        if (result.finalResult) {
          final words = result.recognizedWords.toLowerCase().trim();
          if (mounted) {
            setState(() {
              _lastCommand = '"$words"';
              _isListening = false;
            });
          }
          _handleCommand(words, tts, locale);
        }
      },
      listenFor: const Duration(seconds: 6),
      pauseFor: const Duration(seconds: 3),
      cancelOnError: true,
    );
  }

  void _handleCommand(String words, TtsService tts, String locale) {
    String? matched;
    outer:
    for (final entry in _commands.entries) {
      for (final kw in entry.value) {
        if (words.contains(kw)) {
          matched = entry.key;
          break outer;
        }
      }
    }

    if (matched == null) {
      if (mounted) setState(() => _lastCommand = 'Not recognised: "$words"');
      // Resume TTS since we paused it
      if (!tts.isPlaying && tts.content != null) tts.togglePause(locale);
      return;
    }

    switch (matched) {
      case 'pause':
        if (tts.isPlaying) tts.togglePause(locale);
        if (mounted) setState(() => _lastCommand = '⏸ Paused');
        break;
      case 'play':
        if (!tts.isPlaying) tts.togglePause(locale);
        if (mounted) setState(() => _lastCommand = '▶ Playing');
        break;
      case 'faster':
        tts.setRate((tts.speechRate + 0.25).clamp(0.5, 2.0), locale);
        if (mounted) setState(() => _lastCommand = '⚡ Speed up');
        if (!tts.isPlaying) tts.togglePause(locale);
        break;
      case 'slower':
        tts.setRate((tts.speechRate - 0.25).clamp(0.5, 2.0), locale);
        if (mounted) setState(() => _lastCommand = '🐢 Slowed down');
        if (!tts.isPlaying) tts.togglePause(locale);
        break;
      case 'forward':
        tts.seekForward(10, locale);
        if (mounted) setState(() => _lastCommand = '⏩ +10 seconds');
        break;
      case 'backward':
        tts.seekBackward(10, locale);
        if (mounted) setState(() => _lastCommand = '⏪ −10 seconds');
        break;
      case 'restart':
        tts.restart(locale);
        if (mounted) setState(() => _lastCommand = '🔄 Restarted');
        break;
      case 'stop':
        tts.stop();
        if (mounted) Navigator.pop(context);
        break;
    }
  }

  // ── Helpers ────────────────────────────────────────────
  String _flagFromLocale(String locale) {
    const flags = {
      'en': '🇺🇸',
      'es': '🇪🇸',
      'fr': '🇫🇷',
      'ar': '🇸🇦',
      'tr': '🇹🇷',
      'zh': '🇨🇳',
    };
    final prefix = locale.split('-').first.split('_').first.toLowerCase();
    return flags[prefix] ?? '🌐';
  }

  String _speedLabel(double rate) {
    if (rate <= 0.8) return 'Slow';
    if (rate <= 1.0) return 'Normal';
    if (rate <= 1.3) return 'Fast';
    if (rate <= 1.6) return 'Very Fast';
    return 'Ultra Fast';
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? bg,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: bg ?? Colors.grey[800],
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  // ── Text with WORD + SENTENCE highlight ────────────────
  Widget _buildHighlightedText(TtsService tts) {
    final text = widget.content;
    if (text.isEmpty) {
      return const Text(
        "No text content available for this file.",
        style: TextStyle(fontSize: 16, height: 1.8, color: Colors.black54),
      );
    }

    final wStart = tts.wordStart.clamp(0, text.length);
    final wEnd = tts.wordEnd.clamp(0, text.length);
    final sStart = tts.sentenceStart.clamp(0, text.length);
    final sEnd = tts.sentenceEnd.clamp(0, text.length);

    if (wStart >= text.length || wStart >= wEnd) {
      return Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          height: 1.8,
          color: Colors.black87,
        ),
      );
    }

    // Build spans: before sentence | sentence before word | WORD | sentence after word | after sentence
    final List<TextSpan> spans = [];

    // Before sentence
    if (sStart > 0) {
      spans.add(TextSpan(text: text.substring(0, sStart)));
    }

    // Sentence highlight region
    if (sStart < sEnd) {
      // Part of sentence before the current word
      if (sStart < wStart) {
        spans.add(
          TextSpan(
            text: text.substring(sStart, wStart),
            style: const TextStyle(
              backgroundColor: Color(0xFFEEF3FF),
              color: Colors.black87,
            ),
          ),
        );
      }

      // Current word — bright highlight
      if (wStart < wEnd) {
        spans.add(
          TextSpan(
            text: text.substring(wStart, wEnd),
            style: const TextStyle(
              backgroundColor: Color(0xFFB3C8FF),
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        );
      }

      // Rest of sentence after word
      if (wEnd < sEnd) {
        spans.add(
          TextSpan(
            text: text.substring(wEnd, sEnd),
            style: const TextStyle(
              backgroundColor: Color(0xFFEEF3FF),
              color: Colors.black87,
            ),
          ),
        );
      }
    }

    // After sentence
    if (sEnd < text.length) {
      spans.add(TextSpan(text: text.substring(sEnd)));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 16,
          height: 1.8,
          color: Colors.black87,
        ),
        children: spans,
      ),
    );
  }

  // ── Voice command button + toast ───────────────────────
  Widget _buildVoiceCommandBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _isListening
            ? const Color(0xFFD4B96A).withOpacity(0.15)
            : Colors.grey[200],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isListening ? const Color(0xFFD4B96A) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          // Mic button
          Semantics(
            label: _isListening ? 'Stop voice command' : 'Start voice command',
            child: GestureDetector(
              onTap: _voiceCommandReady ? _toggleVoiceCommand : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isListening
                      ? const Color(0xFFD4B96A)
                      : Colors.grey[800],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: _isListening ? Colors.black : Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isListening ? 'Listening for command...' : 'Voice Commands',
                  style: TextStyle(
                    color: Colors.grey[800],
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _lastCommand.isEmpty
                      ? 'Say: play · pause · faster · slower · forward · back'
                      : _lastCommand,
                  style: TextStyle(
                    color: _lastCommand.isEmpty
                        ? Colors.grey[500]
                        : Colors.grey[700],
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!_voiceCommandReady)
            Icon(Icons.mic_off, color: Colors.grey[400], size: 18),
        ],
      ),
    );
  }

  // ── Speed panel ────────────────────────────────────────
  Widget _buildSpeedPanel(TtsService tts, String locale) {
    final rate = tts.speechRate;
    final wordCount = widget.content.split(RegExp(r'\s+')).length;
    final minutes = (wordCount / (150 * rate)).round();
    final durationLabel = minutes < 60
        ? '~${minutes.toString().padLeft(2, '0')}:00'
        : '~${(minutes / 60).toStringAsFixed(1)}h';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Text(
            _speedLabel(rate),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Duration: $durationLabel',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
          const SizedBox(height: 18),

          // − BIG_SPEED +
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                label: 'Decrease speed',
                child: _circleButton(
                  icon: Icons.remove,
                  onTap: () =>
                      tts.setRate((rate - 0.05).clamp(0.5, 2.0), locale),
                ),
              ),
              const SizedBox(width: 28),
              Text(
                '${rate.toStringAsFixed(2)}x',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 28),
              Semantics(
                label: 'Increase speed',
                child: _circleButton(
                  icon: Icons.add,
                  onTap: () =>
                      tts.setRate((rate + 0.05).clamp(0.5, 2.0), locale),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Preset chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _speedPresets.map((s) {
                final selected = (rate - s).abs() < 0.03;
                return Semantics(
                  label: '${s}x speed',
                  selected: selected,
                  child: GestureDetector(
                    onTap: () => tts.setRate(s, locale),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFD4B96A)
                            : Colors.grey[800],
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        '${s}x',
                        style: TextStyle(
                          color: selected ? Colors.black : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Auto-speed toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Increase Speed Automatically',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Increases speed every 600 words',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                  ],
                ),
                const Spacer(),
                Switch(
                  value: _autoSpeed,
                  onChanged: (v) => setState(() => _autoSpeed = v),
                  activeColor: const Color(0xFFD4B96A),
                  inactiveTrackColor: Colors.grey[700],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Playback bar ────────────────────────────────────────
  Widget _buildPlaybackBar(TtsService tts, String locale) {
    final flag = _flagFromLocale(locale);
    final rate = tts.speechRate;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: _showSpeedPanel
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Voice flag
          Semantics(
            label: 'Change voice',
            child: GestureDetector(
              onTap: () => tts.showVoicePicker(context),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(flag, style: const TextStyle(fontSize: 26)),
                ),
              ),
            ),
          ),

          // Seek back 10s
          Semantics(
            label: 'Go back 10 seconds',
            child: GestureDetector(
              onTap: () => tts.seekBackward(10, locale),
              child: Icon(Icons.replay_10, color: Colors.grey[300], size: 34),
            ),
          ),

          // Play / Pause
          Semantics(
            label: tts.isPlaying ? 'Pause' : 'Play',
            child: GestureDetector(
              onTap: () => tts.togglePause(locale),
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFD4B96A),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  tts.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.black,
                  size: 34,
                ),
              ),
            ),
          ),

          // Seek forward 10s
          Semantics(
            label: 'Skip forward 10 seconds',
            child: GestureDetector(
              onTap: () => tts.seekForward(10, locale),
              child: Icon(Icons.forward_10, color: Colors.grey[300], size: 34),
            ),
          ),

          // Speed badge
          Semantics(
            label: 'Speed ${rate.toStringAsFixed(2)}x, tap to change',
            child: GestureDetector(
              onTap: () => setState(() => _showSpeedPanel = !_showSpeedPanel),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _showSpeedPanel
                      ? const Color(0xFFD4B96A)
                      : Colors.grey[800],
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    rate.toStringAsFixed(2),
                    style: TextStyle(
                      color: _showSpeedPanel ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tts = context.watch<TtsService>();
    final locale = context.watch<LanguageProvider>().ttsLocale;

    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Semantics(
                    label: 'Go back',
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.keyboard_arrow_down, size: 32),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Semantics(
                    label: 'Stop reading and close',
                    child: GestureDetector(
                      onTap: () async {
                        await tts.stop();
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Icon(
                        Icons.close,
                        color: Colors.grey[700],
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Progress bar ──────────────────────────────
            LinearProgressIndicator(
              value: tts.progress,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFD4B96A),
              ),
              minHeight: 3,
            ),

            // ── Scrollable text ───────────────────────────
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: _buildHighlightedText(tts),
              ),
            ),

            // ── Voice command bar ─────────────────────────
            _buildVoiceCommandBar(),

            // ── Speed panel (animated) ────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => SizeTransition(
                sizeFactor: animation,
                axisAlignment: 1.0,
                child: child,
              ),
              child: _showSpeedPanel
                  ? _buildSpeedPanel(tts, locale)
                  : const SizedBox.shrink(),
            ),

            // ── Playback bar ──────────────────────────────
            _buildPlaybackBar(tts, locale),
          ],
        ),
      ),
    );
  }
}
