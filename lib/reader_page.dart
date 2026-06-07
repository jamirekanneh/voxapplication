import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'tts_service.dart';
import 'language_provider.dart';
import 'ai_result_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'analytics_service.dart';
import 'pdf_service.dart';
import 'document_chat_buddy_sheet.dart';
import 'services/mic_coordinator.dart';
import 'services/app_route_observer.dart';
import 'services/reading_voice_commands.dart';

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

class _ReaderPageState extends State<ReaderPage> with RouteAware {
  final ScrollController _scrollController = ScrollController();

  bool _showSpeedPanel = false;
  bool _autoSpeed = false;
  // Pinned highlight — set when user says "highlight text"
  bool _hasPinnedHighlight = false;
  int _pinnedStart = 0;
  int _pinnedEnd = 0;

  static const List<double> _speedPresets = [
    0.4,
    0.5,
    0.6,
    0.8,
    1.0,
    1.25,
    1.5,
  ];

  @override
  void initState() {
    super.initState();
    MicCoordinator.instance.setReaderVoiceActive(true);
    ReadingVoiceCommands.onHighlightSentence = _pinCurrentSentence;

    // Clean content for reading (strip XML tags if detected in docx/xml)
    final tts = context.read<TtsService>();
    final cleaned = widget.content
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final finalContent = cleaned.isEmpty ? widget.content : cleaned;

    if (!tts.isPlaying || tts.title != widget.title) {
      tts.play(widget.title, finalContent, widget.locale);
    }

    // Listener for auto-scrolling
    tts.addListener(_onTtsUpdate);

    // Track file read operation
    AnalyticsService.instance.recordFileOperation('read');
  }

  void _pinCurrentSentence(TtsService tts) {
    if (!mounted) return;
    setState(() {
      _hasPinnedHighlight = true;
      _pinnedStart = tts.sentenceStart;
      _pinnedEnd = tts.sentenceEnd;
    });
    _scrollToHighlight();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  void _setGlobalMiniPlayerSuppressed(bool suppress) {
    context.read<TtsService>().setSuppressGlobalMiniPlayer(suppress);
  }

  @override
  void didPush() {
    _setGlobalMiniPlayerSuppressed(true);
  }

  @override
  void didPopNext() {
    _setGlobalMiniPlayerSuppressed(true);
  }

  @override
  void didPushNext() {
    // Another route covers the reader — show global mini player on that page.
    _setGlobalMiniPlayerSuppressed(false);
  }

  @override
  void didPop() {
    _setGlobalMiniPlayerSuppressed(false);
  }

  void _onTtsUpdate() {
    if (!mounted) return;
    final tts = context.read<TtsService>();
    if (tts.isPlaying) {
      _scrollToHighlight();
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    if (ReadingVoiceCommands.onHighlightSentence == _pinCurrentSentence) {
      ReadingVoiceCommands.onHighlightSentence = null;
    }
    MicCoordinator.instance.setReaderVoiceActive(false);
    final tts = context.read<TtsService>();
    tts.setSuppressGlobalMiniPlayer(false);
    tts.removeListener(_onTtsUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToHighlight() {
    if (!_scrollController.hasClients) return;
    final tts = context.read<TtsService>();
    final text = widget.content;
    if (text.isEmpty) return;

    // Estimate position based on character offset
    final progress = tts.sentenceStart / text.length;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final target = progress * maxScroll;

    _scrollController.animateTo(
      (target - 100).clamp(0, maxScroll),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

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
          source: 'Home',
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
    final text = tts.content ?? '';
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
        style: const TextStyle(fontSize: 16, height: 1.8, color: Colors.white),
      );
    }

    final lang = context.watch<LanguageProvider>();
    final isDyslexic = lang.isDyslexicFontEnabled;
    final isBionic = lang.isBionicReadingEnabled;

    return RichText(
      text: TextSpan(
        style: isDyslexic
            ? GoogleFonts.lexend(
                fontSize: 20,
                height: 1.8,
                color: Colors.white,
                letterSpacing: 1.2,
              )
            : const TextStyle(
                fontSize: 20,
                height: 1.6,
                color: Colors.white,
                letterSpacing: 0.2,
                fontFamily: 'Inter',
              ),
        children: [
          if (sStart > 0)
            _processTextSpan(
              text.substring(0, sStart),
              isBionic,
              false,
              isDyslexic,
            ),
          _processTextSpan(
            text.substring(sStart, sEnd),
            isBionic,
            true,
            isDyslexic,
          ),
          if (sEnd < text.length)
            _processTextSpan(text.substring(sEnd), isBionic, false, isDyslexic),
        ],
      ),
    );
  }

  TextSpan _processTextSpan(
    String text,
    bool isBionic,
    bool isHighlighted,
    bool isDyslexic,
  ) {
    if (!isBionic) {
      return TextSpan(
        text: text,
        style: isHighlighted
            ? TextStyle(
                backgroundColor: const Color(0xFF4B9EFF).withValues(alpha: 0.2),
                color: const Color(0xFF4B9EFF),
                fontWeight: FontWeight.w900,
                decoration: TextDecoration.underline,
                decorationThickness: 2,
                decorationColor: const Color(0xFF4B9EFF).withValues(alpha: 0.5),
              )
            : null,
      );
    }

    // Bionic Reading logic: bold the first half of each word
    final words = text.split(RegExp(r'(\s+)'));
    return TextSpan(
      children: words.map((w) {
        if (w.trim().isEmpty) return TextSpan(text: w);

        int boldLen = (w.length / 2).ceil().clamp(1, w.length);
        return TextSpan(
          children: [
            TextSpan(
              text: w.substring(0, boldLen),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: isHighlighted ? const Color(0xFF4B9EFF) : Colors.white,
                backgroundColor: isHighlighted
                    ? const Color(0xFF4B9EFF).withValues(alpha: 0.2)
                    : null,
              ),
            ),
            TextSpan(
              text: w.substring(boldLen),
              style: TextStyle(
                fontWeight: FontWeight.w300,
                color: isHighlighted
                    ? const Color(0xFF4B9EFF).withValues(alpha: 0.8)
                    : Colors.white70,
                backgroundColor: isHighlighted
                    ? const Color(0xFF4B9EFF).withValues(alpha: 0.2)
                    : null,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  // ── Study Buddy Chat ────────────────────────────
  void _showStudyBuddySheet() {
    DocumentChatBuddySheet.show(
      context,
      documentTitle: widget.title,
      documentContent: widget.content,
    );
  }

  void _showSettingsSheet(LanguageProvider lang) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141A29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const Text(
                'Reader Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                title: const Text(
                  'OpenDyslexic Font',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Enhanced readability for dyslexia',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                value: lang.isDyslexicFontEnabled,
                activeThumbColor: const Color(0xFF4B9EFF),
                onChanged: (v) async {
                  await lang.setDyslexicFont(v);
                  if (!mounted) return;
                  setState(() {});
                  setSheetState(() {});
                },
              ),
              SwitchListTile(
                title: const Text(
                  'Bionic Reading',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Highlight word starts for faster focus',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                value: lang.isBionicReadingEnabled,
                activeThumbColor: const Color(0xFF4B9EFF),
                onChanged: (v) async {
                  await lang.setBionicReading(v);
                  if (!mounted) return;
                  setState(() {});
                  setSheetState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── AI Tools bar ──────────────────────────────
  Widget _buildAiBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
            // Q&A Generator button
            GestureDetector(
              onTap: () => _openAiPage('flashcards'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF4B9EFF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.style_outlined,
                      color: Color(0xFF0A0E1A),
                      size: 13,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Q&A Generator',
                      style: TextStyle(
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
            // Study Buddy Button
            GestureDetector(
              onTap: _showStudyBuddySheet,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.psychology,
                      color: Colors.purpleAccent,
                      size: 13,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Study Buddy',
                      style: TextStyle(
                        color: Colors.purpleAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // PDF Button
            GestureDetector(
              onTap: () => PdfService.exportSummaryPdf(
                context,
                widget.title,
                widget.content,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.picture_as_pdf_outlined,
                      color: Colors.blue,
                      size: 13,
                    ),
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
          ],
        ),
      ),
    );
  }

  // ── Speed panel ───────────────────────────────────────
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

  // ── Playback bar ──────────────────────────────────────
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
            behavior: HitTestBehavior.opaque,
            onTap: () => tts.skipBackward(10, locale),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.replay_10, color: Colors.grey[300], size: 34),
            ),
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
            behavior: HitTestBehavior.opaque,
            onTap: () => tts.skipForward(10, locale),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.forward_10, color: Colors.grey[300], size: 34),
            ),
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

  // ── Build ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final tts = context.watch<TtsService>();
    final locale = context.watch<LanguageProvider>().ttsLocale;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
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
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        _showSettingsSheet(context.read<LanguageProvider>()),
                    child: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white70,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () async {
                      await tts.stop();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Icon(
                      Icons.close,
                      color: Colors.white70,
                      size: 24,
                    ),
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
