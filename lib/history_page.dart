import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'language_provider.dart';
import 'theme_provider.dart';

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
      backgroundColor: VoxColors.bg(context),
      appBar: AppBar(
        title: Text(
          t('history_title'),
          style: TextStyle(color: VoxColors.onBg(context)),
        ),
        backgroundColor: VoxColors.surface(context),
        elevation: 0,
        iconTheme: IconThemeData(color: VoxColors.onBg(context)),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: VoxColors.primary(context)),
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
            return Center(
              child: CircularProgressIndicator(color: VoxColors.primary(context)),
            );
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Text(
                t('history_empty'),
                style: TextStyle(color: VoxColors.textSecondary(context)),
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
                    color: VoxColors.surface2(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  child: Icon(Icons.delete, color: VoxColors.danger),
                ),
                secondaryBackground: Container(
                  decoration: BoxDecoration(
                    color: VoxColors.surface2(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: Icon(Icons.delete, color: VoxColors.danger),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: VoxColors.surface(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: VoxColors.border(context)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    title: Text(
                      doc["word"],
                      style: TextStyle(
                        color: VoxColors.onSurface(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: VoxColors.textHint(context),
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
