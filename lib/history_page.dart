import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'language_provider.dart';

class HistoryScreen extends StatelessWidget {
  HistoryScreen({super.key});

  final user = FirebaseAuth.instance.currentUser;

  CollectionReference get historyRef => FirebaseFirestore.instance
      .collection('users')
      .doc(user!.uid)
      .collection('history');

  Future<void> addWord(String word) async {
    await historyRef.add({"word": word, "time": FieldValue.serverTimestamp()});
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final t = lang.t;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF), // Same as homepage
      appBar: AppBar(
        title: Text(
          t('history_title'),
          style: const TextStyle(color: Color(0xFF0A0E1A)),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0A0E1A)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF0A0E1A)),
            onPressed: () {
              addWord("Word ${DateTime.now().second}");
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: historyRef.orderBy("time", descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF0A0E1A)),
            );
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Text(
                t('history_empty'),
                style: const TextStyle(color: Color(0x8A0A0E1A)),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];

              return Dismissible(
                key: Key(doc.id),
                direction: DismissDirection.horizontal,
                onDismissed: (_) async {
                  await historyRef.doc(doc.id).delete();
                },
                background: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  child: const Icon(Icons.delete, color: Color(0xFF333333)),
                ),
                secondaryBackground: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Color(0xFF333333)),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF0A0E1A).withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    title: Text(
                      doc["word"],
                      style: const TextStyle(
                        color: Color(0xDD0A0E1A),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Color(0x730A0E1A),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

