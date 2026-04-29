import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'pdf_service.dart';
import 'ai_service.dart';

class AiResultPage extends StatefulWidget {
  final String documentTitle;
  final String documentContent;
  final String mode; // 'summary' | 'flashcards'
  final int cardCount; // how many flashcards to generate
  final String source; // 'Home' | 'Notes' — origin of the document

  const AiResultPage({
    super.key,
    required this.documentTitle,
    required this.documentContent,
    required this.mode,
    this.cardCount = 10,
    this.source = 'Home',
  });

  @override
  State<AiResultPage> createState() => _AiResultPageState();
}

class _AiResultPageState extends State<AiResultPage> {
  // ── AI State ───────────────────────────────────
  bool _loading = true;
  String? _error;
  String? _summary;
  List<Flashcard>? _flashcards;

  // Flashcard state
  late List<bool> _flipped;
  int _currentCard = 0;

  // ── TTS State ──────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _autoReadEnabled = true; // auto-read toggle

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

  // ── Init TTS ───────────────────────────────────
  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  // ── TTS helpers ────────────────────────────────
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
    if (widget.mode == 'summary') return _summary ?? '';
    if (_flashcards == null || _flashcards!.isEmpty) return '';
    final card = _flashcards![_currentCard];
    return _flipped[_currentCard]
        ? 'Answer: ${card.answer}'
        : 'Question: ${card.question}';
  }

  // ── Fetch AI content ───────────────────────────
  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _stopSpeaking();
    try {
      if (widget.mode == 'summary') {
        final s = await AiService.summarize(widget.documentContent);
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
            _speak('Question 1: ${cards.first.question}');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  // ── Save to Firebase ───────────────────────────
  Future<void> _saveAssessment() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to save assessments.')),
      );
      return;
    }

    if (_flashcards == null || _flashcards!.isEmpty) return;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: widget.documentTitle);
        return AlertDialog(
          backgroundColor: const Color(0xFF161B2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Save Assessment',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter Chapter or Document Name:',
                style: TextStyle(fontSize: 13, color: Color(0xAA0A0E1A)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Chapter 1 Biology',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A0E1A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) return;

    setState(() => _loading = true);

    try {
      final data = _flashcards!
          .map((f) => {'question': f.question, 'answer': f.answer})
          .toList();
      await FirebaseFirestore.instance.collection('assessments').add({
        'userId': user.uid,
        'userEmail': user.email,
        'documentTitle': result,
        'source': widget.source,
        'createdAt': FieldValue.serverTimestamp(),
        'questions': data,
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved successfully!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Speaker button ─────────────────────────────
  Widget _buildSpeakerButton({bool compact = false}) {
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
              ? const Color(0xFF4B9EFF)
              : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
              size: 15,
              color: _isSpeaking ? Color(0xFF0A0E1A) : Color(0x8A0A0E1A),
            ),
            if (!compact) ...[
              const SizedBox(width: 5),
              Text(
                _isSpeaking ? 'Stop' : 'Read Aloud',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _isSpeaking ? Color(0xFF0A0E1A) : Color(0x8A0A0E1A),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Auto-read toggle ───────────────────────────
  Widget _buildAutoReadToggle() {
    return GestureDetector(
      onTap: () {
        setState(() => _autoReadEnabled = !_autoReadEnabled);
        if (!_autoReadEnabled) _stopSpeaking();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _autoReadEnabled
              ? const Color(0xFF4B9EFF).withOpacity(0.15)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _autoReadEnabled ? const Color(0xFF4B9EFF) : Colors.white10,
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
              _autoReadEnabled ? 'Auto ON' : 'Auto OFF',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _autoReadEnabled
                    ? const Color(0xFF4B9EFF)
                    : Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Summary view ──────────────────────────────
  Widget _buildSummary() {
    final lines = (_summary ?? '').split('\n');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: lines.length,
      itemBuilder: (_, i) {
        final line = lines[i].trim();
        if (line.isEmpty) return const SizedBox(height: 10);
        final isBullet = line.startsWith('•');
        return Padding(
          padding: EdgeInsets.only(bottom: 6, left: isBullet ? 8 : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isBullet) ...[
                const Text(
                  '•  ',
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFF4B9EFF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: Text(
                    line.substring(1).trim(),
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.55,
                      color: Colors.white,
                    ),
                  ),
                ),
              ] else
                Expanded(
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.65,
                      color: Colors.white70,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Flashcard view ────────────────────────────
  Widget _buildFlashcards() {
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
                'Card ${_currentCard + 1} of ${cards.length}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _buildSpeakerButton(compact: true),
              const SizedBox(width: 8),
              Text(
                'Tap to flip',
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
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
              backgroundColor: Colors.white.withOpacity(0.05),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF4B9EFF),
              ),
              minHeight: 4,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Flashcard — tap flips and reads
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() => _flipped[_currentCard] = !_flipped[_currentCard]);
              final newText = _flipped[_currentCard]
                  ? 'Answer: ${card.answer}'
                  : 'Question: ${card.question}';
              if (_autoReadEnabled) _speak(newText);
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Container(
                key: ValueKey('${_currentCard}_$isFlipped'),
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: isFlipped
                      ? const Color(0xFF161B2E)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF0A0E1A).withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: isFlipped
                        ? const Color(0xFF4B9EFF).withOpacity(0.4)
                        : Colors.white.withOpacity(0.08),
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
                            ? const Color(0xFF4B9EFF).withOpacity(0.15)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isFlipped ? 'ANSWER' : 'QUESTION',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: isFlipped
                              ? const Color(0xFF4B9EFF)
                              : Colors.grey[500],
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
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Icon(
                      Icons.touch_app_outlined,
                      size: 14,
                      color: isFlipped ? Colors.grey[600] : Colors.grey[400],
                    ),
                    Text(
                      'Tap to flip',
                      style: TextStyle(
                        fontSize: 10,
                        color: isFlipped ? Colors.grey[600] : Colors.grey[400],
                      ),
                    ),
                  ],
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
                                'Question ${_currentCard + 1}: ${_flashcards![_currentCard].question}',
                              );
                            });
                          }
                        }
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: _currentCard > 0
                          ? Colors.white.withOpacity(0.2)
                          : Colors.white.withOpacity(0.05),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '← Previous',
                    style: TextStyle(fontWeight: FontWeight.w700),
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
                                'Question ${_currentCard + 1}: ${_flashcards![_currentCard].question}',
                              );
                            });
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4B9EFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    disabledBackgroundColor: Colors.white.withOpacity(0.05),
                  ),
                  child: const Text(
                    'Next →',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isSummary = widget.mode == 'summary';
    final title = isSummary ? 'Summary' : 'Assessment';

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
                    onTap: () {
                      _stopSpeaking();
                      Navigator.pop(context);
                    },
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          widget.documentTitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Auto-read toggle
                  if (!_loading && _error == null) _buildAutoReadToggle(),
                  const SizedBox(width: 6),
                  // Speaker button (summary only — flashcard has its own)
                  if (!_loading && _error == null && isSummary)
                    _buildSpeakerButton(),
                  const SizedBox(width: 6),

                  // Save button (assessments only)
                  if (!_loading && _error == null && !isSummary)
                    GestureDetector(
                      onTap: _saveAssessment,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4B9EFF).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF4B9EFF).withOpacity(0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bookmark_add_outlined,
                              size: 16,
                              color: Color(0xFF4B9EFF),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Save',
                              style: TextStyle(
                                color: Color(0xFF4B9EFF),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),

                  // Download PDF button
                  if (!_loading && _error == null)
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 16,
                              color: Colors.blue,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'PDF',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),

                  // Retry
                  if (!_loading)
                    GestureDetector(
                      onTap: _fetch,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.refresh,
                          size: 20,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const Divider(height: 1, color: Colors.white10),

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
                                ? 'Generating summary...'
                                : 'Creating ${widget.cardCount} questions...',
                            style: const TextStyle(color: Colors.white54),
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
                            const Icon(
                              Icons.error_outline,
                              size: 48,
                              color: Color(0x610A0E1A),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Something went wrong',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0x8A0A0E1A),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _fetch,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFF0A0E1A),
                                foregroundColor: const Color(0xFFF0F4FF),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 14,
                                ),
                              ),
                              child: const Text('Try Again'),
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
