import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'pdf_service.dart';
import 'ai_service.dart';
import 'language_provider.dart';
import 'services/document_language_service.dart';
import 'services/saved_docs_service.dart';
import 'theme_provider.dart';

class AiResultPage extends StatefulWidget {
  final String documentTitle;
  final String documentContent;
  final String mode; // 'summary' | 'flashcards'
  final int cardCount;
  final String outputLanguage;
  final String source; // 'Home' | 'Notes' â€” origin of the document

  const AiResultPage({
    super.key,
    required this.documentTitle,
    required this.documentContent,
    required this.mode,
    this.cardCount = 10,
    this.source = 'Home',
    this.outputLanguage = 'English',
  });

  @override
  State<AiResultPage> createState() => _AiResultPageState();
}

class _AiResultPageState extends State<AiResultPage> {
  // â”€â”€ AI State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _loading = true;
  String? _error;
  String? _summary;
  List<Flashcard>? _flashcards;

  // Flashcard state
  late List<bool> _flipped;
  int _currentCard = 0;

  // â”€â”€ TTS State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _autoReadEnabled = true; // auto-read toggle

  String get _ttsLocale =>
      DocumentLanguageService.ttsLocaleForLanguage(widget.outputLanguage);

  bool _isBulletLine(String line) {
    if (line.startsWith('\u2022') || line.startsWith('*')) return true;
    if (line.startsWith('- ') || line == '-') return true;
    return RegExp(r'^\d+[.)]\s').hasMatch(line);
  }

  String _bulletBody(String line) {
    if (line.startsWith('\u2022') || line.startsWith('*')) {
      return line.substring(1).trim();
    }
    if (line.startsWith('- ')) return line.substring(2).trim();
    if (line.startsWith('-')) return line.substring(1).trim();
    final match = RegExp(r'^\d+[.)]\s*(.*)').firstMatch(line);
    if (match != null) return (match.group(1) ?? line).trim();
    return line;
  }

  @override
  void initState() {
    super.initState();
    _initTts();
    _fetch();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  // â”€â”€ Init TTS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _initTts() async {
    await _tts.setLanguage(_ttsLocale);
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  // â”€â”€ TTS helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _speak(String text) async {
    await _tts.stop();
    if (text.isEmpty) return;
    setState(() => _isSpeaking = true);
    await _tts.speak(text);
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    if (mounted) setState(() => _isSpeaking = false);
  }

  void _toggleSpeaker() {
    if (_isSpeaking) {
      _stopSpeaking();
    } else {
      _speak(_currentSpeakText());
    }
  }

  String _currentSpeakText() {
    final lang = context.read<LanguageProvider>();
    if (widget.mode == 'summary') return _summary ?? '';
    if (_flashcards == null || _flashcards!.isEmpty) return '';
    final card = _flashcards![_currentCard];
    return _flipped[_currentCard]
        ? lang.tNamed('speak_answer', {'text': card.answer})
        : lang.tNamed('speak_question', {'text': card.question});
  }

  // â”€â”€ Fetch AI content â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _fetch() async {
    final lang = context.read<LanguageProvider>();
    setState(() {
      _loading = true;
      _error = null;
    });
    await _stopSpeaking();
    try {
      if (widget.documentContent.trim().isEmpty) {
        throw Exception(lang.t('no_text_to_analyze'));
      }
      if (widget.mode == 'summary') {
        final s = await AiService.summarize(
          widget.documentContent,
          outputLanguage: widget.outputLanguage,
        );
        if (mounted) {
          setState(() {
            _summary = s;
            _loading = false;
          });
          // Auto-read summary
          if (_autoReadEnabled) {
            await Future.delayed(const Duration(milliseconds: 400));
            _speak(s);
          }
        }
      } else {
        final cards = await AiService.generateFlashcards(
          widget.documentContent,
          count: widget.cardCount,
          outputLanguage: widget.outputLanguage,
        );
        if (mounted) {
          setState(() {
            _flashcards = cards;
            _flipped = List.filled(cards.length, false);
            _loading = false;
          });
          // Auto-read first question
          if (_autoReadEnabled && cards.isNotEmpty) {
            await Future.delayed(const Duration(milliseconds: 400));
            _speak(
              lang.tNamed(
                'speak_question_n',
                {'n': '1', 'text': cards.first.question},
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '').trim();
          _loading = false;
        });
      }
    }
  }

  Future<String?> _promptSaveTitle(String dialogTitle) async {
    final lang = context.read<LanguageProvider>();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: widget.documentTitle);
        return AlertDialog(
          backgroundColor: VoxColors.surface(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            dialogTitle,
            style: TextStyle(
              color: VoxColors.onSurface(ctx),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lang.t('title_for_saved_docs'),
                style: TextStyle(
                  fontSize: 13,
                  color: VoxColors.textSecondary(ctx),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                style: TextStyle(color: VoxColors.onSurface(ctx)),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: lang.t('title_hint_saved_docs'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(lang.t('cancel'), style: const TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4B9EFF),
                foregroundColor: Colors.white,
              ),
              child: Text(lang.t('save_label')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveToSavedDocs() async {
    final lang = context.read<LanguageProvider>();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.t('sign_in_to_save_docs'))),
      );
      return;
    }

    final isSummary = widget.mode == 'summary';
    if (isSummary && (_summary == null || _summary!.trim().isEmpty)) return;
    if (!isSummary && (_flashcards == null || _flashcards!.isEmpty)) return;

    final title = await _promptSaveTitle(
      isSummary ? lang.t('save_summary_title') : lang.t('save_qa_title'),
    );
    if (title == null || title.isEmpty) return;

    setState(() => _loading = true);
    try {
      final ok = isSummary
          ? await SavedDocsService.saveSummary(
              title: title,
              summary: _summary!,
              source: widget.source,
            )
          : await SavedDocsService.saveQa(
              title: title,
              questions: _flashcards!
                  .map((f) => {'question': f.question, 'answer': f.answer})
                  .toList(),
              source: widget.source,
            );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok ? lang.t('saved_to_menu_docs') : lang.t('could_not_save_document'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${lang.t('error_saving')} $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // â”€â”€ Speaker button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildSpeakerButton({bool compact = false}) {
    final lang = context.watch<LanguageProvider>();
    return GestureDetector(
      onTap: _toggleSpeaker,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: _isSpeaking
              ? VoxColors.primary(context)
              : VoxColors.cardFill(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
              size: 15,
              color: _isSpeaking
                  ? VoxColors.onPrimary(context)
                  : VoxColors.onBg(context).withValues(alpha: 0.54),
            ),
            if (!compact) ...[
              const SizedBox(width: 5),
              Text(
                _isSpeaking ? lang.t('stop_speaking') : lang.t('read_aloud'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _isSpeaking
                      ? VoxColors.onPrimary(context)
                      : VoxColors.onBg(context).withValues(alpha: 0.54),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // â”€â”€ Auto-read toggle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildAutoReadToggle() {
    final lang = context.watch<LanguageProvider>();
    return GestureDetector(
      onTap: () {
        setState(() => _autoReadEnabled = !_autoReadEnabled);
        if (!_autoReadEnabled) _stopSpeaking();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _autoReadEnabled
              ? VoxColors.primary(context).withValues(alpha: 0.15)
              : VoxColors.cardFill(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _autoReadEnabled
                ? VoxColors.primary(context)
                : VoxColors.border(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _autoReadEnabled ? Icons.autorenew : Icons.autorenew,
              size: 13,
              color: _autoReadEnabled ? Colors.green : Colors.grey[500],
            ),
            const SizedBox(width: 4),
            Text(
              _autoReadEnabled ? lang.t('auto_on') : lang.t('auto_off'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _autoReadEnabled
                    ? VoxColors.primary(context)
                    : VoxColors.textHint(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€ Summary view â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildSummary() {
    final lines = (_summary ?? '').split('\n');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: lines.length,
      itemBuilder: (_, i) {
        final line = lines[i].trim();
        if (line.isEmpty) return const SizedBox(height: 10);
        final isBullet = _isBulletLine(line);
        return Padding(
          padding: EdgeInsets.only(bottom: 6, left: isBullet ? 8 : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isBullet) ...[
                const Text(
                  '\u2022  ',
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFF4B9EFF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: Text(
                    _bulletBody(line),
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.55,
                      color: VoxColors.onSurface(context),
                    ),
                  ),
                ),
              ] else
                Expanded(
                  child: Text(
                    line,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.65,
                      color: VoxColors.textSecondary(context),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // â”€â”€ Flashcard view â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildFlashcards() {
    final lang = context.watch<LanguageProvider>();
    final cards = _flashcards!;
    final card = cards[_currentCard];
    final isFlipped = _flipped[_currentCard];

    return Column(
      children: [
        // Progress + speaker
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              Text(
                lang.tNamed('card_progress', {
                  'current': '${_currentCard + 1}',
                  'total': '${cards.length}',
                }),
                style: TextStyle(
                  color: VoxColors.textMuted(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _buildSpeakerButton(compact: true),
              const SizedBox(width: 8),
              Text(
                lang.t('tap_to_flip'),
                style: TextStyle(
                  color: VoxColors.textMuted(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),

        // Progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_currentCard + 1) / cards.length,
              backgroundColor: VoxColors.surfaceMuted(context),
              valueColor: AlwaysStoppedAnimation<Color>(
                VoxColors.primary(context),
              ),
              minHeight: 4,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Flashcard â€” tap flips and reads
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() => _flipped[_currentCard] = !_flipped[_currentCard]);
              final newText = _flipped[_currentCard]
                  ? lang.tNamed('speak_answer', {'text': card.answer})
                  : lang.tNamed('speak_question', {'text': card.question});
              if (_autoReadEnabled) _speak(newText);
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Theme(
                data: ThemeData(
                  brightness: Brightness.light,
                  textTheme: const TextTheme(
                    bodyMedium: TextStyle(color: Color(0xFF0A0E1A)),
                    bodySmall: TextStyle(color: Color(0xFF0A0E1A)),
                    labelSmall: TextStyle(color: Color(0xFF0A0E1A)),
                  ),
                  iconTheme: const IconThemeData(color: Color(0xFF0A0E1A)),
                ),
                child: Container(
                key: ValueKey('${_currentCard}_$isFlipped'),
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: isFlipped
                      ? VoxColors.flashcardFillAlt(context)
                      : VoxColors.flashcardFill(context),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: isFlipped
                        ? VoxColors.primary(context).withValues(alpha: 0.4)
                        : VoxColors.borderStrong(context),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isFlipped
                            ? VoxColors.primary(context).withValues(alpha: 0.15)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isFlipped
                            ? lang.t('flashcard_answer')
                            : lang.t('flashcard_question'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: isFlipped
                              ? VoxColors.primary(context)
                              : VoxColors.flashcardText(context)
                                  .withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      isFlipped ? card.answer : card.question,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.6,
                        fontWeight: FontWeight.w700,
                        color: VoxColors.flashcardText(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Icon(
                      Icons.touch_app_outlined,
                      size: 14,
                      color: VoxColors.flashcardText(context)
                          .withValues(alpha: 0.45),
                    ),
                    Text(
                      lang.t('tap_to_flip'),
                      style: TextStyle(
                        fontSize: 10,
                        color: VoxColors.flashcardText(context)
                            .withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ),

        // Navigation
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _currentCard > 0
                      ? () {
                          _stopSpeaking();
                          setState(() {
                            _currentCard--;
                            _flipped[_currentCard] = false;
                          });
                          if (_autoReadEnabled) {
                            Future.delayed(const Duration(milliseconds: 200), () {
                              _speak(
                                lang.tNamed('speak_question_n', {
                                  'n': '${_currentCard + 1}',
                                  'text': _flashcards![_currentCard].question,
                                }),
                              );
                            });
                          }
                        }
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: VoxColors.onBg(context),
                    side: BorderSide(
                      color: _currentCard > 0
                          ? VoxColors.borderStrong(context)
                          : VoxColors.border(context),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    lang.t('previous_card'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _currentCard < cards.length - 1
                      ? () {
                          _stopSpeaking();
                          setState(() {
                            _currentCard++;
                            _flipped[_currentCard] = false;
                          });
                          if (_autoReadEnabled) {
                            Future.delayed(const Duration(milliseconds: 200), () {
                              _speak(
                                lang.tNamed('speak_question_n', {
                                  'n': '${_currentCard + 1}',
                                  'text': _flashcards![_currentCard].question,
                                }),
                              );
                            });
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VoxColors.primary(context),
                    foregroundColor: VoxColors.onPrimary(context),
                    disabledForegroundColor: VoxColors.textHint(context),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    disabledBackgroundColor: VoxColors.surfaceMuted(context),
                  ),
                  child: Text(
                    lang.t('next_card'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBarActions({required bool isSummary}) {
    final lang = context.watch<LanguageProvider>();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildAutoReadToggle(),
          const SizedBox(width: 8),
          if (isSummary) _buildSpeakerButton(compact: true),
          if (isSummary) const SizedBox(width: 8),
          GestureDetector(
            onTap: _saveToSavedDocs,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF4B9EFF).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF4B9EFF).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.bookmark_add_outlined,
                    size: 16,
                    color: Color(0xFF4B9EFF),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    lang.t('save_label'),
                    style: const TextStyle(
                      color: Color(0xFF4B9EFF),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              if (isSummary && _summary != null) {
                PdfService.exportSummaryPdf(
                  context,
                  widget.documentTitle,
                  _summary!,
                );
              } else if (!isSummary && _flashcards != null) {
                final qList = _flashcards!
                    .map(
                      (f) => {
                        'question': f.question,
                        'answer': f.answer,
                      },
                    )
                    .toList();
                PdfService.exportAssessmentPdf(
                  context,
                  widget.documentTitle,
                  qList,
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: VoxColors.cardFill(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: VoxColors.border(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 16,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'PDF',
                    style: TextStyle(
                      color: VoxColors.onBg(context),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar({required bool isSummary, required String title}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  _stopSpeaking();
                  Navigator.pop(context);
                },
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 32,
                  color: VoxColors.onBg(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: VoxColors.onBg(context),
                      ),
                    ),
                    Text(
                      widget.documentTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: VoxColors.textMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_loading)
                GestureDetector(
                  onTap: _fetch,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: VoxColors.cardFill(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.refresh,
                      size: 20,
                      color: VoxColors.textSecondary(context),
                    ),
                  ),
                ),
            ],
          ),
          if (!_loading && _error == null) ...[
            const SizedBox(height: 10),
            _buildTopBarActions(isSummary: isSummary),
          ],
        ],
      ),
    );
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final isSummary = widget.mode == 'summary';
    final title =
        isSummary ? lang.t('ai_summary') : lang.t('qa_generator');

    return Scaffold(
      backgroundColor: VoxColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isSummary: isSummary, title: title),

            Divider(height: 1, color: VoxColors.border(context)),

            // Body
            Expanded(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: Color(0xFF4B9EFF),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isSummary
                                ? lang.t('generating_summary')
                                : lang.tNamed('creating_questions', {
                                    'count': '${widget.cardCount}',
                                  }),
                            style: TextStyle(
                              color: VoxColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 48,
                              color: VoxColors.textHint(context),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              lang.t('something_went_wrong'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: VoxColors.onBg(context),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: VoxColors.textSecondary(context),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _fetch,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: VoxColors.primary(context),
                                foregroundColor: VoxColors.onPrimary(context),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 14,
                                ),
                              ),
                              child: Text(lang.t('try_again')),
                            ),
                          ],
                        ),
                      ),
                    )
                  : isSummary
                  ? _buildSummary()
                  : _buildFlashcards(),
            ),
          ],
        ),
      ),
    );
  }
}

