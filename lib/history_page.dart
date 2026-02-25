import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text("History"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
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
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("No history"));
          }

          return ListView.builder(
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
                  color: Colors.red,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                secondaryBackground: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                child: ListTile(title: Text(doc["word"])),
              );
            },
          );
        },
      ),
    );
  }
}
