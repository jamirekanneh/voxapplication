import 'dart:async';

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
import 'services/library_highlight_service.dart';
import 'services/document_language_service.dart';
import 'services/reading_voice_commands.dart';
import 'theme_provider.dart';

class ReaderPage extends StatefulWidget {
  final String title;
  final String content;
  final String locale;
  final String? libraryDocId;
  final bool guestLibrary;
  final int? savedHighlightStart;
  final int? savedHighlightEnd;
  final List<HighlightRange> savedHighlights;

  const ReaderPage({
    super.key,
    required this.title,
    required this.content,
    required this.locale,
    this.libraryDocId,
    this.guestLibrary = false,
    this.savedHighlightStart,
    this.savedHighlightEnd,
    this.savedHighlights = const [],
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with RouteAware {
  final ScrollController _scrollController = ScrollController();

  bool _showSpeedPanel = false;
  bool _autoSpeed = false;
  late String _readingLocale;
  // Pinned highlights — voice "highlight" pins sentences in red (saved to library).
  List<HighlightRange> _pinnedHighlights = [];

  static const Color _pinnedHighlightColor = Color(0xFFE53935);

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
    _readingLocale = DocumentLanguageService.detectTtsLocale(
      widget.content,
      fallbackLanguage:
          DocumentLanguageService.languageNameFromTtsLocale(widget.locale),
    );
    MicCoordinator.instance.setReaderVoiceActive(true);
    ReadingVoiceCommands.onHighlightSentence = _pinCurrentSentence;

    // Clean content for reading (strip XML tags if detected in docx/xml)
    final tts = context.read<TtsService>();
    final cleaned = widget.content
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final finalContent = cleaned.isEmpty ? widget.content : cleaned;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ttsNow = context.read<TtsService>();
      if (ttsNow.isPlaying &&
          ttsNow.title == widget.title &&
          ttsNow.content == finalContent) {
        return;
      }
      await ttsNow.play(widget.title, finalContent, _readingLocale);
    });

    _pinnedHighlights = List<HighlightRange>.from(widget.savedHighlights);
    final savedStart = widget.savedHighlightStart;
    final savedEnd = widget.savedHighlightEnd;
    if (savedStart != null &&
        savedEnd != null &&
        savedEnd > savedStart &&
        savedEnd <= finalContent.length) {
      final legacy = HighlightRange(savedStart, savedEnd);
      if (!_pinnedHighlights.contains(legacy)) {
        _pinnedHighlights = [..._pinnedHighlights, legacy];
      }
    }
    _pinnedHighlights.sort((a, b) => a.start.compareTo(b.start));
    if (_pinnedHighlights.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToHighlight();
      });
    }

    // Listener for auto-scrolling
    tts.addListener(_onTtsUpdate);

    // Track file read operation
    AnalyticsService.instance.recordFileOperation('read');
  }

  void _pinCurrentSentence(TtsService tts) {
    if (!mounted) return;
    final span = tts.sentenceSpanForVoiceHighlight();
    if (span == null || span.end <= span.start) return;

    final range = HighlightRange(span.start, span.end);
    if (_pinnedHighlights.contains(range)) {
      _scrollToHighlight();
      return;
    }

    setState(() {
      _pinnedHighlights = [..._pinnedHighlights, range]
        ..sort((a, b) => a.start.compareTo(b.start));
    });
    _scrollToHighlight();

    if (widget.libraryDocId != null) {
      unawaited(
        LibraryHighlightService.addHighlight(
          context: context,
          fileName: widget.title,
          start: range.start,
          end: range.end,
          libraryDocId: widget.libraryDocId,
          guestLibrary: widget.guestLibrary,
          existing: _pinnedHighlights,
        ),
      );
    }
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
    final text = tts.content ?? widget.content;
    if (text.isEmpty) return;

    final offset = _pinnedHighlights.isNotEmpty
        ? _pinnedHighlights.last.start
        : tts.sentenceStart;
    final progress = offset / text.length;
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
    if (tts.isPlaying) tts.togglePause(_readingLocale);

    int cardCount = 10;
    if (mode == 'flashcards') {
      final picked = await _pickCardCount();
      if (picked == null || !mounted) return;
      cardCount = picked;
    }

    if (!mounted) return;
    final outputLanguage = context.read<LanguageProvider>().selectedLanguage;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiResultPage(
          documentTitle: widget.title,
          documentContent: widget.content,
          mode: mode,
          cardCount: cardCount,
          source: 'Home',
          outputLanguage: outputLanguage,
        ),
      ),
    );
  }

  Future<int?> _pickCardCount() async {
    final lang = context.read<LanguageProvider>();
    int selected = 10;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFFF0F4FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            lang.t('how_many_questions'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                lang.tNamed('cards_count', {'count': '$selected'}),
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
              child: Text(
                lang.t('cancel'),
                style: const TextStyle(color: Color(0x8A0A0E1A)),
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
              child: Text(lang.t('generate')),
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

  List<HighlightRange> _mergedPinnedHighlights(String text) {
    if (_pinnedHighlights.isEmpty) return const [];
    final sorted = List<HighlightRange>.from(_pinnedHighlights)
      ..sort((a, b) => a.start.compareTo(b.start));
    final merged = <HighlightRange>[];
    for (final raw in sorted) {
      final start = raw.start.clamp(0, text.length);
      final end = raw.end.clamp(start, text.length);
      if (end <= start) continue;
      final range = HighlightRange(start, end);
      if (merged.isEmpty) {
        merged.add(range);
        continue;
      }
      final last = merged.last;
      if (range.start <= last.end) {
        merged[merged.length - 1] = HighlightRange(
          last.start,
          range.end > last.end ? range.end : last.end,
        );
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  // ── Highlighted text (pinned red only — no live TTS tracking) ──
  Widget _buildHighlightedText() {
    final text = context.read<TtsService>().content ?? widget.content;
    if (text.isEmpty) {
      return Text(
        'No text content available for this file.',
        style: TextStyle(
          fontSize: 16,
          height: 1.8,
          color: VoxColors.textSecondary(context),
        ),
      );
    }

    final lang = context.watch<LanguageProvider>();
    final isDyslexic = lang.isDyslexicFontEnabled;
    final isBionic = lang.isBionicReadingEnabled;
    final textColor = VoxColors.onBg(context);
    final baseStyle = isDyslexic
        ? GoogleFonts.lexend(
            fontSize: 20,
            height: 1.8,
            color: textColor,
            letterSpacing: 1.2,
          )
        : TextStyle(
            fontSize: 20,
            height: 1.6,
            color: textColor,
            letterSpacing: 0.2,
            fontFamily: 'Inter',
          );

    final ranges = _mergedPinnedHighlights(text);
    if (ranges.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final children = <InlineSpan>[];
    var pos = 0;
    for (final range in ranges) {
      if (range.start > pos) {
        children.add(
          _processTextSpan(
            text.substring(pos, range.start),
            isBionic,
            false,
            isDyslexic,
            textColor,
          ),
        );
      }
      if (range.end > range.start) {
        children.add(
          _processTextSpan(
            text.substring(range.start, range.end),
            isBionic,
            true,
            isDyslexic,
            textColor,
          ),
        );
      }
      pos = range.end;
    }
    if (pos < text.length) {
      children.add(
        _processTextSpan(
          text.substring(pos),
          isBionic,
          false,
          isDyslexic,
          textColor,
        ),
      );
    }

    return RichText(text: TextSpan(style: baseStyle, children: children));
  }

  TextSpan _processTextSpan(
    String text,
    bool isBionic,
    bool isHighlighted,
    bool isDyslexic,
    Color textColor,
  ) {
    final secondaryColor = VoxColors.textSecondary(context);
    if (!isBionic) {
      return TextSpan(
        text: text,
        style: isHighlighted
            ? TextStyle(
                backgroundColor: _pinnedHighlightColor.withValues(alpha: 0.25),
                color: _pinnedHighlightColor,
                fontWeight: FontWeight.w900,
                decoration: TextDecoration.underline,
                decorationThickness: 2,
                decorationColor: _pinnedHighlightColor.withValues(alpha: 0.6),
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
                color: isHighlighted ? _pinnedHighlightColor : textColor,
                backgroundColor: isHighlighted
                    ? _pinnedHighlightColor.withValues(alpha: 0.25)
                    : null,
              ),
            ),
            TextSpan(
              text: w.substring(boldLen),
              style: TextStyle(
                fontWeight: FontWeight.w300,
                color: isHighlighted
                    ? _pinnedHighlightColor.withValues(alpha: 0.85)
                    : secondaryColor,
                backgroundColor: isHighlighted
                    ? _pinnedHighlightColor.withValues(alpha: 0.25)
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

  Future<void> _setReadingLanguage(String languageName) async {
    final newLocale = DocumentLanguageService.ttsLocaleForLanguage(languageName);
    if (newLocale == _readingLocale) return;
    setState(() => _readingLocale = newLocale);
    final tts = context.read<TtsService>();
    await tts.switchReadingLocale(newLocale);
  }

  void _showSettingsSheet(LanguageProvider lang) {
    showModalBottomSheet(
      context: context,
      backgroundColor: VoxColors.surface(context),
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
              Text(
                lang.t('reader_settings_title'),
                style: TextStyle(
                  color: VoxColors.onSurface(context),
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  lang.t('reader_reading_language'),
                  style: TextStyle(
                    color: VoxColors.onSurface(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                lang.t('reader_reading_language_hint'),
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: DocumentLanguageService.languageNames.map((name) {
                  final locale = DocumentLanguageService.ttsLocaleForLanguage(name);
                  final selected = _readingLocale == locale;
                  return ChoiceChip(
                    label: Text(
                      '${_flagFromLocale(locale)} $name',
                      style: TextStyle(
                        color: selected
                            ? VoxColors.onPrimary(context)
                            : VoxColors.onSurface(context),
                        fontSize: 12,
                      ),
                    ),
                    selected: selected,
                    selectedColor: VoxColors.primary(context),
                    backgroundColor: VoxColors.surface2(context),
                    onSelected: (_) {
                      Navigator.pop(ctx);
                      unawaited(_setReadingLanguage(name));
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text(
                  'OpenDyslexic Font',
                  style: TextStyle(color: VoxColors.onSurface(context)),
                ),
                subtitle: Text(
                  'Enhanced readability for dyslexia',
                  style: TextStyle(
                    color: VoxColors.textSecondary(context),
                    fontSize: 12,
                  ),
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
                title: Text(
                  'Bionic Reading',
                  style: TextStyle(color: VoxColors.onSurface(context)),
                ),
                subtitle: Text(
                  'Highlight word starts for faster focus',
                  style: TextStyle(
                    color: VoxColors.textSecondary(context),
                    fontSize: 12,
                  ),
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
    final lang = context.watch<LanguageProvider>();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: VoxColors.cardFill(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VoxColors.border(context)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 15, color: VoxColors.primary(context)),
            const SizedBox(width: 8),
            Text(
              lang.t('ai_tools'),
              style: const TextStyle(
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
                  color: VoxColors.surfaceMuted(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: VoxColors.border(context)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.summarize_outlined,
                      color: VoxColors.onBg(context),
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      lang.t('summarize'),
                      style: TextStyle(
                        color: VoxColors.onBg(context),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.style_outlined,
                      color: Color(0xFF0A0E1A),
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      lang.t('qa_generator'),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.psychology,
                      color: Colors.purpleAccent,
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      lang.t('study_buddy'),
                      style: const TextStyle(
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
        color: VoxColors.surface(context),
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
            style: TextStyle(
              color: VoxColors.onSurface(context),
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
                style: TextStyle(
                  color: VoxColors.onSurface(context),
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
                          ? VoxColors.primary(context)
                          : VoxColors.surface2(context),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      '${s}x',
                      style: TextStyle(
                        color: selected
                            ? VoxColors.onPrimary(context)
                            : VoxColors.onSurface(context),
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
              color: VoxColors.surface2(context),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Increase Speed Automatically',
                      style: TextStyle(
                        color: VoxColors.onSurface(context),
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
        color: VoxColors.surface(context),
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
                color: VoxColors.surface2(context),
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
              child: Icon(
                Icons.replay_10,
                color: VoxColors.textSecondary(context),
                size: 34,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => tts.togglePause(locale),
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
              child: Icon(
                Icons.forward_10,
                color: VoxColors.textSecondary(context),
                size: 34,
              ),
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
                    ? VoxColors.primary(context)
                    : VoxColors.surface2(context),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  rate.toStringAsFixed(2),
                  style: TextStyle(
                    color: _showSpeedPanel
                        ? VoxColors.onPrimary(context)
                        : VoxColors.onSurface(context),
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
    final locale = _readingLocale;

    return Scaffold(
      backgroundColor: VoxColors.bg(context),
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
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 32,
                      color: VoxColors.onBg(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: VoxColors.onBg(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        _showSettingsSheet(context.read<LanguageProvider>()),
                    child: Icon(
                      Icons.settings_outlined,
                      color: VoxColors.textSecondary(context),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () async {
                      await tts.stop();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Icon(
                      Icons.close,
                      color: VoxColors.textSecondary(context),
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
              child: Directionality(
                textDirection: DocumentLanguageService.isRtlLocale(_readingLocale)
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: _buildHighlightedText(),
                ),
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
