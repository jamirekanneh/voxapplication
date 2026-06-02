import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SavedDocEntry {
  final String id;
  final bool legacy;
  final String type;
  final String title;
  final String source;
  final Timestamp? createdAt;
  final Map<String, dynamic> data;

  const SavedDocEntry({
    required this.id,
    required this.legacy,
    required this.type,
    required this.title,
    required this.source,
    required this.createdAt,
    required this.data,
  });
}

/// Persisted AI summaries, Q&A sets, and saved note transcripts.
class SavedDocsService {
  SavedDocsService._();

  static const typeSummary = 'summary';
  static const typeQa = 'qa';
  static const typeNote = 'note';

  static CollectionReference<Map<String, dynamic>> _userDocs(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('saved_docs');

  static Future<String?> _requireUid() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;
    return user.uid;
  }

  static Future<bool> saveSummary({
    required String title,
    required String summary,
    required String source,
  }) async {
    final uid = await _requireUid();
    if (uid == null) return false;
    await _userDocs(uid).add({
      'userId': uid,
      'type': typeSummary,
      'title': title,
      'content': summary,
      'source': source,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  static Future<bool> saveQa({
    required String title,
    required List<Map<String, String>> questions,
    required String source,
  }) async {
    final uid = await _requireUid();
    if (uid == null) return false;
    await _userDocs(uid).add({
      'userId': uid,
      'type': typeQa,
      'title': title,
      'questions': questions,
      'source': source,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  static Future<bool> saveNote({
    required String title,
    required String content,
    required String source,
    String? noteId,
  }) async {
    final uid = await _requireUid();
    if (uid == null) return false;
    await _userDocs(uid).add({
      'userId': uid,
      'type': typeNote,
      'title': title,
      'content': content,
      'source': source,
      if (noteId != null && noteId.isNotEmpty) 'noteId': noteId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchUserDocs(String uid) {
    return _userDocs(uid).snapshots();
  }

  /// Legacy top-level collection from earlier app versions.
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchLegacyAssessments(
    String uid,
  ) {
    return FirebaseFirestore.instance
        .collection('assessments')
        .where('userId', isEqualTo: uid)
        .snapshots();
  }

  static Future<void> deleteDoc({
    required String uid,
    required String docId,
    required bool legacy,
  }) async {
    if (legacy) {
      await FirebaseFirestore.instance
          .collection('assessments')
          .doc(docId)
          .delete();
    } else {
      await _userDocs(uid).doc(docId).delete();
    }
  }
}
