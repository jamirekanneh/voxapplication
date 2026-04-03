import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RecycleBinPage extends StatelessWidget {
  final String? resolvedUid;
  const RecycleBinPage({super.key, this.resolvedUid});

  String get _uid => resolvedUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference get _bin => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('deleted_library');

  Future<void> _restore(BuildContext context, DocumentSnapshot doc) async {
    try {
      final data = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
      data.remove('deletedAt');

      final sourceCol = data['sourceCollection'] as String?;
      final isNote = sourceCol == 'notes';

      if (isNote) {
        data['title'] = data['fileName'];
        data.remove('fileName');
        data.remove('sourceCollection');
        data.remove('fileType');
      }

      data['userId'] = _uid;
      data['timestamp'] = data['originalTimestamp'] ?? FieldValue.serverTimestamp();
      data.remove('originalTimestamp');

      final targetCollection = isNote ? 'notes' : 'library';
      await FirebaseFirestore.instance.collection(targetCollection).add(data);
      await _bin.doc(doc.id).delete();

      if (context.mounted) {
        final itemName = isNote ? data['title'] : data['fileName'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$itemName" restored.'),
            backgroundColor: const Color(0xFFD4B96A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restore failed.')),
        );
      }
    }
  }

  Future<void> _permanentDelete(BuildContext context, DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['fileName'] as String? ?? 'File';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text('"$name" will be gone forever.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _bin.doc(doc.id).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      appBar: AppBar(
        title: const Text('Recycle Bin', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _bin.orderBy('deletedAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 64, color: Colors.grey[400]),
                  const Text('Your recycle bin is empty', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final name = data['fileName'] as String? ?? 'Unknown';
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  leading: const Icon(Icons.insert_drive_file, color: Color(0xFFD4B96A)),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.restore, color: Colors.green), onPressed: () => _restore(context, doc)),
                      IconButton(icon: const Icon(Icons.delete_forever, color: Colors.redAccent), onPressed: () => _permanentDelete(context, doc)),
                    ],
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
