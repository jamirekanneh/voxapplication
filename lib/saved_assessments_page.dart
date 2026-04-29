import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ai_service.dart';

class SavedAssessmentsPage extends StatefulWidget {
  const SavedAssessmentsPage({super.key});

  @override
  State<SavedAssessmentsPage> createState() => _SavedAssessmentsPageState();
}

class _SavedAssessmentsPageState extends State<SavedAssessmentsPage> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  // ── Source filter ('All' | 'Home' | 'Notes') ────────────────────────
  String _filter = 'All';

  void _openAssessment(Map<String, dynamic> data) async {
    final questionsList = data['questions'] as List<dynamic>?;
    if (questionsList == null) return;

    final List<Flashcard> flashcards = questionsList.map((e) {
      final m = e as Map<String, dynamic>;
      return Flashcard(question: m['question'] ?? '', answer: m['answer'] ?? '');
    }).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssessmentViewerScreen(
          title: data['documentTitle'] ?? 'Saved Assessment',
          flashcards: flashcards,
        ),
      ),
    );
  }

  void _confirmDelete(String docId, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Assessment?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Delete "$title"? This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseFirestore.instance
                  .collection('assessments')
                  .doc(docId)
                  .delete();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Assessment deleted.'),
                    backgroundColor: const Color(0xFF1E2540),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252).withOpacity(0.85),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Delete',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Source badge ─────────────────────────────────────────────────────
  Widget _sourceBadge(String source) {
    final isHome = source == 'Home';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isHome
            ? const Color(0xFF4B9EFF).withOpacity(0.12)
            : const Color(0xFF9B59B6).withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isHome
              ? const Color(0xFF4B9EFF).withOpacity(0.3)
              : const Color(0xFF9B59B6).withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isHome ? Icons.home_outlined : Icons.mic_none_rounded,
            size: 10,
            color: isHome ? const Color(0xFF4B9EFF) : const Color(0xFF9B59B6),
          ),
          const SizedBox(width: 4),
          Text(
            source,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: isHome
                  ? const Color(0xFF4B9EFF)
                  : const Color(0xFF9B59B6),
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter chip ──────────────────────────────────────────────────────
  Widget _filterChip(String label, IconData icon) {
    final selected = _filter == label;
    return GestureDetector(
      onTap: () => setState(() => _filter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF4B9EFF)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF4B9EFF)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: selected ? const Color(0xFF0A0E1A) : Colors.white60),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? const Color(0xFF0A0E1A) : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null || currentUser!.isAnonymous) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'Saved Assessments',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF4B9EFF).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    color: Color(0xFF4B9EFF), size: 38),
              ),
              const SizedBox(height: 20),
              const Text(
                'Sign in required',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20),
              ),
              const SizedBox(height: 8),
              Text(
                'Please sign in to view your\nsaved assessments.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.5), height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saved Assessments',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Your Q&A flashcard sets',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Bookmarks icon accent
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4B9EFF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF4B9EFF).withOpacity(0.2)),
                    ),
                    child: const Icon(Icons.bookmarks_outlined,
                        color: Color(0xFF4B9EFF), size: 18),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Filter chips ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _filterChip('All', Icons.apps_rounded),
                  const SizedBox(width: 8),
                  _filterChip('Home', Icons.home_outlined),
                  const SizedBox(width: 8),
                  _filterChip('Notes', Icons.mic_none_rounded),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1, color: Colors.white10),

            // ── List ──────────────────────────────────────────────────
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('assessments')
                    .where('userId', isEqualTo: currentUser!.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF4B9EFF), strokeWidth: 2),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error loading assessments: ${snapshot.error}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    );
                  }

                  // Load all docs and sort in-memory to avoid needing a composite index
                  final allDocs = snapshot.data?.docs ?? [];
                  final sortedDocs = List<QueryDocumentSnapshot>.from(allDocs)
                    ..sort((a, b) {
                      final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                      final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                      if (aTime == null || bTime == null) return 0;
                      return bTime.compareTo(aTime); // Descending
                    });

                  // Apply source filter
                  final docs = _filter == 'All'
                      ? sortedDocs
                      : sortedDocs.where((d) {
                          final data = d.data() as Map<String, dynamic>;
                          return (data['source'] as String? ?? 'Home') ==
                              _filter;
                        }).toList();

                  if (allDocs.isEmpty) {
                    return _emptyState();
                  }

                  if (docs.isEmpty) {
                    return _filteredEmptyState();
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data =
                          docs[index].data() as Map<String, dynamic>;
                      final title =
                          data['documentTitle'] ?? 'Untitled Assessment';
                      final questions =
                          (data['questions'] as List?)?.length ?? 0;
                      final source =
                          data['source'] as String? ?? 'Home';
                      final timestamp =
                          (data['createdAt'] as Timestamp?)?.toDate();
                      final dateStr = timestamp != null
                          ? '${timestamp.day}/${timestamp.month}/${timestamp.year}'
                          : '—';

                      return GestureDetector(
                        onTap: () => _openAssessment(data),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.08)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                // Icon
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4B9EFF)
                                        .withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.style_outlined,
                                      color: Color(0xFF4B9EFF), size: 22),
                                ),
                                const SizedBox(width: 12),

                                // Content
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Title + source badge row
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                                fontSize: 14,
                                              ),
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _sourceBadge(source),
                                        ],
                                      ),
                                      const SizedBox(height: 5),

                                      // Meta row
                                      Row(
                                        children: [
                                          Icon(Icons.quiz_outlined,
                                              size: 11,
                                              color: Colors.white
                                                  .withOpacity(0.4)),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$questions question${questions == 1 ? '' : 's'}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white
                                                  .withOpacity(0.45),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Icon(Icons.calendar_today_outlined,
                                              size: 11,
                                              color: Colors.white
                                                  .withOpacity(0.4)),
                                          const SizedBox(width: 4),
                                          Text(
                                            dateStr,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white
                                                  .withOpacity(0.45),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Delete
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent, size: 20),
                                  onPressed: () => _confirmDelete(
                                      docs[index].id, title),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF4B9EFF).withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bookmarks_outlined,
                  color: Color(0xFF4B9EFF), size: 36),
            ),
            const SizedBox(height: 20),
            const Text(
              'No assessments yet',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20),
            ),
            const SizedBox(height: 10),
            Text(
              'Generate a Q&A Assessment from any document in Home or note in Notes, then tap Save.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 13,
                  height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filteredEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_list_off_rounded,
              color: Colors.white.withOpacity(0.2), size: 48),
          const SizedBox(height: 16),
          Text(
            'No $_filter assessments',
            style: const TextStyle(
                color: Colors.white60, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ── Lightweight Assessment Viewer ────────────────────────────────────────────
class AssessmentViewerScreen extends StatefulWidget {
  final String title;
  final List<Flashcard> flashcards;

  const AssessmentViewerScreen({
    super.key,
    required this.title,
    required this.flashcards,
  });

  @override
  State<AssessmentViewerScreen> createState() => _AssessmentViewerScreenState();
}

class _AssessmentViewerScreenState extends State<AssessmentViewerScreen> {
  int _currentCard = 0;
  late List<bool> _flipped;

  @override
  void initState() {
    super.initState();
    _flipped = List.filled(widget.flashcards.length, false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.flashcards.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Text('No cards', style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    final card = widget.flashcards[_currentCard];
    final isFlipped = _flipped[_currentCard];
    final total = widget.flashcards.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            letterSpacing: -0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Card ${_currentCard + 1} of $total',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Progress bar ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_currentCard + 1) / total,
                  backgroundColor: Colors.white.withOpacity(0.05),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF4B9EFF)),
                  minHeight: 3,
                ),
              ),
            ),

            const Divider(height: 1, color: Colors.white10),
            const SizedBox(height: 8),

            // ── Tap hint ─────────────────────────────────────────────
            Text(
              'Tap card to reveal answer',
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
            ),

            // ── Flashcard ─────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: GestureDetector(
                  onTap: () => setState(
                      () => _flipped[_currentCard] = !isFlipped),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Container(
                      key: ValueKey('${_currentCard}_$isFlipped'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: isFlipped
                            ? const Color(0xFF161B2E)
                            : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isFlipped
                              ? const Color(0xFF4B9EFF).withOpacity(0.35)
                              : Colors.white.withOpacity(0.08),
                        ),
                        boxShadow: [
                          if (isFlipped)
                            BoxShadow(
                              color:
                                  const Color(0xFF4B9EFF).withOpacity(0.08),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Label pill
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 5),
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
                            style: const TextStyle(
                              fontSize: 18,
                              height: 1.6,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Icon(
                            Icons.touch_app_outlined,
                            size: 14,
                            color: isFlipped
                                ? Colors.grey[700]
                                : Colors.grey[500],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Navigation ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _currentCard > 0
                          ? () => setState(() {
                                _currentCard--;
                                _flipped[_currentCard] = false;
                              })
                          : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(
                          color: _currentCard > 0
                              ? Colors.white.withOpacity(0.18)
                              : Colors.white.withOpacity(0.05),
                        ),
                        foregroundColor: Colors.white70,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('← Previous',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _currentCard < total - 1
                          ? () => setState(() {
                                _currentCard++;
                                _flipped[_currentCard] = false;
                              })
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4B9EFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        disabledBackgroundColor:
                            Colors.white.withOpacity(0.05),
                        elevation: 0,
                      ),
                      child: const Text('Next →',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
