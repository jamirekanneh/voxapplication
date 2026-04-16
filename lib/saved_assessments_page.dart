import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ai_result_page.dart';
import 'ai_service.dart';

class SavedAssessmentsPage extends StatefulWidget {
  const SavedAssessmentsPage({super.key});

  @override
  State<SavedAssessmentsPage> createState() => _SavedAssessmentsPageState();
}

class _SavedAssessmentsPageState extends State<SavedAssessmentsPage> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  void _openAssessment(Map<String, dynamic> data) async {
    final questionsList = data['questions'] as List<dynamic>?;
    if (questionsList == null) return;

    // Convert dynamic list to Flashcard models
    final List<Flashcard> flashcards = questionsList.map((e) {
      final m = e as Map<String, dynamic>;
      return Flashcard(
        question: m['question'] ?? '',
        answer: m['answer'] ?? '',
      );
    }).toList();

    // Push standard AI result page but we bypass generation since we already have cards
    // Wait, AiResultPage doesn't take pre-generated cards. 
    // It always generates them from text. 
    // We should create a lightweight viewer here or update AiResultPage
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssessmentViewerScreen(
            title: data['documentTitle'] ?? 'Q&A Generator',
          flashcards: flashcards,
        ),
      ),
    );
  }

  void _confirmDelete(String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFF0F4FF),
        title: const Text('Delete Q&A Generator?'),
        content: const Text('Are you sure you want to delete this saved Q&A Generator?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0x8A0A0E1A))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseFirestore.instance.collection('assessments').doc(docId).delete();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Q&A Generator deleted.')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null || currentUser!.isAnonymous) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F4FF),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: Text("Please sign in to view saved Q&A Generators.")),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Saved Q&A Generator', style: TextStyle(color: Color(0xFF0A0E1A), fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Color(0xFF0A0E1A)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('assessments')
            .where('userId', isEqualTo: currentUser!.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF0A0E1A)));
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error loading Q&A Generators: ${snapshot.error}"));
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text("No saved Q&A Generators yet. Generate some and save them!"));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final title = data['documentTitle'] ?? 'Untitled Q&A Generator';
              final questions = (data['questions'] as List?)?.length ?? 0;
              final timestamp = (data['createdAt'] as Timestamp?)?.toDate();

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Color(0xFF0A0E1A).withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF4B9EFF),
                    child: Icon(Icons.style_outlined, color: Colors.white),
                  ),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('$questions questions • ${timestamp?.month}/${timestamp?.day}/${timestamp?.year}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () => _confirmDelete(docs[index].id),
                  ),
                  onTap: () => _openAssessment(data),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Lightweight Assessment Viewer ───────────────────────────────────
class AssessmentViewerScreen extends StatefulWidget {
  final String title;
  final List<Flashcard> flashcards;

  const AssessmentViewerScreen({super.key, required this.title, required this.flashcards});

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
    if (widget.flashcards.isEmpty) return Scaffold(appBar: AppBar(), body: const Center(child: Text("No cards")));

    final card = widget.flashcards[_currentCard];
    final isFlipped = _flipped[_currentCard];

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(color: Color(0xFF0A0E1A))),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0A0E1A)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Card ${_currentCard + 1} of ${widget.flashcards.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _flipped[_currentCard] = !isFlipped),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Container(
                  key: ValueKey('${_currentCard}_$isFlipped'),
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: isFlipped ? const Color(0xFF1A1A1A) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Color(0xFF0A0E1A).withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 6))],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(isFlipped ? 'ANSWER' : 'QUESTION', style: TextStyle(color: isFlipped ? const Color(0xFF4B9EFF) : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 24),
                        Text(
                          isFlipped ? card.answer : card.question,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, color: isFlipped ? Colors.white : Color(0xDD0A0E1A)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _currentCard > 0 ? () => setState(() { _currentCard--; _flipped[_currentCard] = false; }) : null,
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: const Text('Previous'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _currentCard < widget.flashcards.length - 1 ? () => setState(() { _currentCard++; _flipped[_currentCard] = false; }) : null,
                    style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF0A0E1A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: const Text('Next'),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
