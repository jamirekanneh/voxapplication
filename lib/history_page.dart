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
      backgroundColor: const Color(0xFFF3E5AB), // Same as homepage
      appBar: AppBar(
        title: Text(
          t('history_title'),
          style: const TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black),
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
              child: CircularProgressIndicator(color: Colors.black),
            );
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Text(
                t('history_empty'),
                style: const TextStyle(color: Colors.black54),
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
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    title: Text(
                      doc["word"],
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.black45,
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
