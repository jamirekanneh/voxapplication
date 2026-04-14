import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'tts_service.dart';
import 'language_provider.dart';
import 'ai_result_page.dart';
import 'analytics_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_service.dart';
import 'pdf_service.dart';

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

  bool _showSpeedPanel = false;
  bool _showCommandsPanel = true;
  bool _speechReady = false;
  bool _isListening = false;
  bool _autoSpeed = false;
  String _commandFeedback = '';

  // Pinned highlight — set when user says "highlight text"
  bool _hasPinnedHighlight = false;
  int _pinnedStart = 0;
  int _pinnedEnd = 0;

  // Always-on listening
  bool _alwaysOnEnabled = true;
  bool _commandProcessing = false;

  // Debounce timer to prevent restart loops
  DateTime _lastRestartTime = DateTime.now();

  static const List<double> _speedPresets = [
    0.4,
    0.5,
    0.6,
    0.8,
    1.0,
    1.25,
    1.5,
  ];

  static const _commandList = [
    ['▶', 'play / resume', 'Resume reading'],
    ['⏸', 'pause / wait', 'Pause reading'],
    ['⏩', 'forward / skip', 'Skip +10 seconds'],
    ['⏪', 'back / rewind', 'Go back −10 seconds'],
    ['⚡', 'faster / speed up', 'Increase speed'],
    ['🐢', 'slower / slow down', 'Decrease speed'],
    ['🔄', 'restart / beginning', 'Start from beginning'],
    ['🛑', 'stop / exit', 'Close reader'],
    ['🔆', 'highlight / mark', 'Highlight last sentence'],
  ];

  @override
  void initState() {
    super.initState();
    final tts = context.read<TtsService>();
    if (!tts.isPlaying || tts.title != widget.title) {
      tts.play(widget.title, widget.content, widget.locale);
    }

    // Track file read operation
    AnalyticsService.instance.recordFileOperation('read');

    _initSpeech();
  }

  @override
  void dispose() {
    _speech.stop();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Init STT ──────────────────────────────────────────
  Future<void> _initSpeech() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;

    final ok = await _speech.initialize(
      onError: (e) {
        if (!mounted) return;
        setState(() => _isListening = false);
        // Auto-restart on error if always-on is enabled, with debounce
        if (_alwaysOnEnabled && !_commandProcessing) {
          _scheduleRestart();
        }
      },
      onStatus: (s) {
        if (!mounted) return;
        if (s == 'done' || s == 'notListening') {
          setState(() => _isListening = false);
          // Auto-restart continuous listening
          if (_alwaysOnEnabled && !_commandProcessing) {
            _scheduleRestart();
          }
        }
      },
    );

    if (mounted) {
      setState(() => _speechReady = ok);
      if (ok && _alwaysOnEnabled) {
        await Future.delayed(const Duration(milliseconds: 300));
        _startAlwaysOnListening();
      }
    }
  }

  /// Debounced restart — prevents tight restart loops
  void _scheduleRestart() {
    final now = DateTime.now();
    // Minimum 500ms between restarts
    final msSinceLast = now.difference(_lastRestartTime).inMilliseconds;
    final delay = msSinceLast < 500 ? 500 - msSinceLast : 150;
    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted && _alwaysOnEnabled && !_commandProcessing && !_isListening) {
        _startAlwaysOnListening();
      }
    });
  }

  // ── Continuous listening (always-on) ──────────────────
  Future<void> _startAlwaysOnListening() async {
    if (!mounted || !_speechReady || _isListening || _commandProcessing) return;
    _lastRestartTime = DateTime.now();

    try {
      setState(() => _isListening = true);

      await _speech.listen(
        localeId: 'en_US',
        // 60s window — engine auto-chunks; onStatus 'done' restarts it
        listenFor: const Duration(seconds: 60),
        // Wait 2.5s of silence before considering the utterance done
        pauseFor: const Duration(seconds: 2, milliseconds: 500),
        partialResults: true,
        cancelOnError: false,
        onResult: (result) {
          if (!mounted || _commandProcessing) return;

          final words = result.recognizedWords.toLowerCase().trim();
          if (words.isEmpty) return;

          // Only act on final results or clear partial matches
          final isFinal = result.finalResult;
          final hasMatch = _matchesAnyCommand(words);

          if (hasMatch && (isFinal || _isHighConfidence(words))) {
            _commandProcessing = true;
            _speech.stop();

            final tts = context.read<TtsService>();
            final locale = context.read<LanguageProvider>().ttsLocale;
            final wasPlaying = tts.isPlaying;

            Future.delayed(const Duration(milliseconds: 100), () {
              _executeCommand(words, tts, locale, wasPlaying);
            });
          }
        },
      );
    } catch (e) {
      debugPrint('STT listen error: $e');
      if (mounted) {
        setState(() => _isListening = false);
        if (_alwaysOnEnabled && !_commandProcessing) _scheduleRestart();
      }
    }
  }

  bool _matchesAnyCommand(String words) {
    return _has(words, ['play', 'resume', 'continue', 'start reading', 'go']) ||
        _has(words, ['pause', 'stop reading', 'wait', 'hold on']) ||
        _has(words, ['forward', 'skip', 'next', 'skip ahead']) ||
        _has(words, ['back', 'backward', 'rewind', 'go back', 'previous']) ||
        _has(words, ['faster', 'speed up', 'increase speed', 'go faster']) ||
        _has(words, ['slower', 'slow down', 'decrease speed', 'go slower']) ||
        _has(words, ['restart', 'start over', 'from the beginning']) ||
        _has(words, ['stop', 'close', 'exit', 'quit reader']) ||
        _has(words, ['highlight', 'mark', 'highlight that', 'mark text']);
  }

  /// High-confidence = very short utterance that's clearly a command keyword
  bool _isHighConfidence(String words) {
    const highConf = [
      'play',
      'pause',
      'stop',
      'forward',
      'back',
      'faster',
      'slower',
      'restart',
      'highlight',
      'mark',
    ];
    final parts = words.split(' ');
    return parts.length <= 3 && highConf.any((k) => words.contains(k));
  }

  // ── Toggle always-on listening ─────────────────────────
  void _toggleAlwaysOn() {
    setState(() => _alwaysOnEnabled = !_alwaysOnEnabled);
    if (_alwaysOnEnabled) {
      _startAlwaysOnListening();
    } else {
      _speech.stop();
      setState(() => _isListening = false);
    }
  }

  void _executeCommand(
    String words,
    TtsService tts,
    String locale,
    bool wasPlaying,
  ) {
    if (!mounted) return;

    String feedback = '❓ Not recognised';
    VoidCallback? action;

    if (_has(words, ['play', 'resume', 'continue', 'start reading', 'go'])) {
      feedback = '▶ Playing';
      action = () {
        if (!tts.isPlaying) tts.togglePause(locale);
      };
    } else if (_has(words, ['pause', 'stop reading', 'wait', 'hold on'])) {
      feedback = '⏸ Paused';
      action = () {
        if (tts.isPlaying) tts.togglePause(locale);
      };
    } else if (_has(words, ['forward', 'skip', 'next', 'skip ahead'])) {
      feedback = '⏩ +10 seconds';
      action = () => tts.seekForward(10, locale);
    } else if (_has(words, [
      'back',
      'backward',
      'rewind',
      'go back',
      'previous',
    ])) {
      feedback = '⏪ −10 seconds';
      action = () => tts.seekBackward(10, locale);
    } else if (_has(words, [
      'faster',
      'speed up',
      'increase speed',
      'go faster',
    ])) {
      feedback = '⚡ Speed up';
      action = () =>
          tts.setRate((tts.speechRate + 0.25).clamp(0.5, 2.0), locale);
    } else if (_has(words, [
      'slower',
      'slow down',
      'decrease speed',
      'go slower',
    ])) {
      feedback = '🐢 Slower';
      action = () =>
          tts.setRate((tts.speechRate - 0.25).clamp(0.5, 2.0), locale);
    } else if (_has(words, ['restart', 'start over', 'from the beginning'])) {
      feedback = '🔄 Restarted';
      action = () => tts.restart(locale);
    } else if (_has(words, ['stop', 'close', 'exit', 'quit reader'])) {
      feedback = '🛑 Stopped';
      action = () {
        tts.stop();
        if (mounted) Navigator.pop(context);
      };
    } else if (_has(words, [
      'highlight',
      'mark',
      'highlight that',
      'mark text',
    ])) {
      feedback = '🔆 Sentence highlighted';
      action = () {
        setState(() {
          _hasPinnedHighlight = true;
          _pinnedStart = tts.sentenceStart;
          _pinnedEnd = tts.sentenceEnd;
        });
      };
    }

    setState(() {
      _isListening = false;
      _commandFeedback = feedback;
    });

    action?.call();

    // Resume always-on listening after command
    _commandProcessing = false;
    if (_alwaysOnEnabled) {
      Future.delayed(
        const Duration(milliseconds: 700),
        _startAlwaysOnListening,
      );
    }
  }

  bool _has(String words, List<String> keywords) =>
      keywords.any((k) => words.contains(k));

  // ── Open AI page ──────────────────────────────
  void _openAiPage(String mode) async {
    final tts = context.read<TtsService>();
    final locale = context.read<LanguageProvider>().ttsLocale;
    if (tts.isPlaying) tts.togglePause(locale);

    int cardCount = 10;
    if (mode == 'flashcards') {
      final picked = await _pickCardCount();
      if (picked == null || !mounted) return;
      cardCount = picked;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiResultPage(
          documentTitle: widget.title,
          documentContent: widget.content,
          mode: mode,
          cardCount: cardCount,
        ),
      ),
    );
  }

  Future<int?> _pickCardCount() async {
    int selected = 10;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFFF0F4FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'How many questions?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$selected cards',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4B9EFF),
                ),
              ),
              Slider(
                value: selected.toDouble(),
                min: 5,
                max: 20,
                divisions: 15,
                activeColor: Color(0xFF0A0E1A),
                inactiveColor: Colors.grey[300],
                onChanged: (v) => setDialogState(() => selected = v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '5',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  Text(
                    '20',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0x8A0A0E1A)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF0A0E1A),
                foregroundColor: const Color(0xFFF0F4FF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────
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
    if (rate <= 0.45) return 'Very Slow';
    if (rate <= 0.55) return 'Normal';
    if (rate <= 0.85) return 'Fast';
    if (rate <= 1.1) return 'Very Fast';
    if (rate <= 1.4) return 'Ultra Fast';
    return 'Insane';
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
          color: bg ?? Color(0xFF1c2333),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  // ── Highlighted text ──────────────────────────
  Widget _buildHighlightedText(TtsService tts) {
    final text = widget.content;
    if (text.isEmpty) {
      return const Text(
        'No text content available for this file.',
        style: TextStyle(fontSize: 16, height: 1.8, color: Color(0x8A0A0E1A)),
      );
    }

    final liveSStart = tts.sentenceStart.clamp(0, text.length);
    final liveSEnd = tts.sentenceEnd.clamp(liveSStart, text.length);
    final sStart = _hasPinnedHighlight
        ? _pinnedStart.clamp(0, text.length)
        : liveSStart;
    final sEnd = _hasPinnedHighlight
        ? _pinnedEnd.clamp(sStart, text.length)
        : liveSEnd;

    if (sStart >= sEnd) {
      return Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          height: 1.8,
          color: Color(0xDD0A0E1A),
        ),
      );
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 16,
          height: 1.8,
          color: Color(0xDD0A0E1A),
        ),
        children: [
          if (sStart > 0) TextSpan(text: text.substring(0, sStart)),
          TextSpan(
            text: text.substring(sStart, sEnd),
            style: TextStyle(
              backgroundColor: _hasPinnedHighlight
                  ? const Color(0xFFFFC107)
                  : const Color(0xFFFFE066),
              color: Color(0xFF0A0E1A),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (sEnd < text.length) TextSpan(text: text.substring(sEnd)),
        ],
      ),
    );
  }

  // ── AI Tools bar ──────────────────────────────
  Widget _buildAiBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color(0xFF0A0E1A).withOpacity(0.08)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 15, color: Color(0xFF4B9EFF)),
            const SizedBox(width: 8),
            const Text(
              'Actions',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Color(0xFF4B9EFF),
              ),
            ),
            const SizedBox(width: 12),
            // Summarize button
            GestureDetector(
              onTap: () => _openAiPage('summary'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Color(0xFF0A0E1A),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.summarize_outlined,
                      color: Color(0xFFF0F4FF),
                      size: 13,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Summarize',
                      style: TextStyle(
                        color: Color(0xFFF0F4FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Assessment button
            GestureDetector(
              onTap: () => _openAiPage('flashcards'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF4B9EFF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.style_outlined, color: Color(0xFF0A0E1A), size: 13),
                    SizedBox(width: 5),
                    Text(
                      'Assessment',
                      style: TextStyle(
                        color: Color(0xFF0A0E1A),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // PDF Button
            GestureDetector(
              onTap: () => PdfService.exportSummaryPdf(context, widget.title, widget.content),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.picture_as_pdf_outlined, color: Colors.blue, size: 13),
                    SizedBox(width: 5),
                    Text(
                      'PDF',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Reminder Button
            GestureDetector(
              onTap: () async {
                final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                if (time != null && mounted) {
                  final now = DateTime.now();
                  var scheduledTime = DateTime(now.year, now.month, now.day, time.hour, time.minute);
                  if (scheduledTime.isBefore(now)) {
                    scheduledTime = scheduledTime.add(const Duration(days: 1));
                  }
                  
                  await NotificationService.scheduleReminder(
                    id: scheduledTime.millisecondsSinceEpoch ~/ 1000,
                    title: 'Study Reminder: ${widget.title}',
                    body: 'It is time to dive back into your reading material!',
                    scheduledTime: scheduledTime,
                  );
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Reminder set for ${time.format(context)}')),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_alarm, color: Colors.orange, size: 13),
                    SizedBox(width: 5),
                    Text(
                      'Remind',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Commands panel ─────────────────────────────────────
  Widget _buildCommandsPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: Color(0xFF141A29),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mic, color: Color(0xFF4B9EFF), size: 14),
              const SizedBox(width: 6),
              const Text(
                'Voice Commands',
                style: TextStyle(
                  color: Color(0xFF4B9EFF),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showCommandsPanel = false),
                child: Icon(Icons.close, color: Colors.grey[500], size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._commandList.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Text('${c[0]}  ', style: const TextStyle(fontSize: 12)),
                  Expanded(
                    child: Text(
                      c[1],
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    c[2],
                    style: TextStyle(color: Colors.grey[500], fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mic bar ────────────────────────────────────────────
  Widget _buildMicBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _isListening ? Colors.green.withOpacity(0.12) : Colors.grey[200],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isListening ? Colors.green : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _isListening
                  ? Colors.green
                  : (_alwaysOnEnabled ? Colors.grey[700] : Colors.grey[400]),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isListening ? Icons.graphic_eq : Icons.mic,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isListening
                      ? 'Listening for commands...'
                      : (_alwaysOnEnabled
                            ? 'Voice commands active'
                            : 'Voice commands off'),
                  style: TextStyle(
                    color: Color(0xFF1c2333),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                if (_commandFeedback.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _commandFeedback,
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // Always-on toggle
          GestureDetector(
            onTap: _toggleAlwaysOn,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _alwaysOnEnabled ? Colors.green : Colors.grey[300],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _alwaysOnEnabled ? Icons.mic : Icons.mic_off,
                    color: Colors.white,
                    size: 13,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _alwaysOnEnabled ? 'ON' : 'OFF',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Toggle commands panel
          GestureDetector(
            onTap: () =>
                setState(() => _showCommandsPanel = !_showCommandsPanel),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _showCommandsPanel
                    ? Icons.keyboard_arrow_down
                    : Icons.help_outline,
                color: Colors.grey[700],
                size: 16,
              ),
            ),
          ),
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
        color: Color(0xFF141A29),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _circleButton(
                icon: Icons.remove,
                onTap: () => tts.setRate((rate - 0.05).clamp(0.5, 2.0), locale),
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
              _circleButton(
                icon: Icons.add,
                onTap: () => tts.setRate((rate + 0.05).clamp(0.5, 2.0), locale),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _speedPresets.map((s) {
                final selected = (rate - s).abs() < 0.03;
                return GestureDetector(
                  onTap: () => tts.setRate(s, locale),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF4B9EFF)
                          : Color(0xFF1c2333),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      '${s}x',
                      style: TextStyle(
                        color: selected ? Color(0xFF0A0E1A) : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Color(0xFF141A29),
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
                  activeThumbColor: const Color(0xFF4B9EFF),
                  inactiveTrackColor: Colors.grey[700],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Playback bar ───────────────────────────────────────
  Widget _buildPlaybackBar(TtsService tts, String locale) {
    final flag = _flagFromLocale(locale);
    final rate = tts.speechRate;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Color(0xFF141A29),
        borderRadius: _showSpeedPanel
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Voice picker
          GestureDetector(
            onTap: () => tts.showVoicePicker(context),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Color(0xFF1c2333),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(flag, style: const TextStyle(fontSize: 26)),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => tts.seekBackward(10, locale),
            child: Icon(Icons.replay_10, color: Colors.grey[300], size: 34),
          ),
          GestureDetector(
            onTap: () {
              if (!tts.isPlaying && _hasPinnedHighlight) {
                setState(() => _hasPinnedHighlight = false);
              }
              tts.togglePause(locale);
            },
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFF4B9EFF),
                shape: BoxShape.circle,
              ),
              child: Icon(
                tts.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Color(0xFF0A0E1A),
                size: 34,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => tts.seekForward(10, locale),
            child: Icon(Icons.forward_10, color: Colors.grey[300], size: 34),
          ),
          // Speed badge
          GestureDetector(
            onTap: () => setState(() => _showSpeedPanel = !_showSpeedPanel),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _showSpeedPanel
                    ? const Color(0xFF4B9EFF)
                    : Color(0xFF1c2333),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  rate.toStringAsFixed(2),
                  style: TextStyle(
                    color: _showSpeedPanel ? Color(0xFF0A0E1A) : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final tts = context.watch<TtsService>();
    final locale = context.watch<LanguageProvider>().ttsLocale;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.keyboard_arrow_down, size: 32),
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
                  GestureDetector(
                    onTap: () async {
                      await tts.stop();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Icon(Icons.close, color: Colors.grey[700], size: 24),
                  ),
                ],
              ),
            ),

            // Progress bar
            LinearProgressIndicator(
              value: tts.progress,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF4B9EFF),
              ),
              minHeight: 3,
            ),

            // Scrollable text
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: _buildHighlightedText(tts),
              ),
            ),

            // ── AI Tools bar (always visible) ──────────
            _buildAiBar(),

            // Commands panel (collapsible)
            if (_showCommandsPanel) _buildCommandsPanel(),

            // Mic bar
            _buildMicBar(),

            // Speed panel (animated)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) => SizeTransition(
                sizeFactor: anim,
                axisAlignment: 1.0,
                child: child,
              ),
              child: _showSpeedPanel
                  ? _buildSpeedPanel(tts, locale)
                  : const SizedBox.shrink(),
            ),

            // Playback bar
            _buildPlaybackBar(tts, locale),
          ],
        ),
      ),
    );
  }
}
