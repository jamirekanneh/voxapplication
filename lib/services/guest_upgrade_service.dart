import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../temp_library_provider.dart';
import '../temp_notes_provider.dart';
import 'email_change_service.dart';

/// Upgrades a guest session to a saved account (device link + cloud data).
class GuestUpgradeService {
  GuestUpgradeService._();

  static Future<bool> emailExistsInSystem(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return false;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: trimmed)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> userHasCloudProfile(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// Merges legacy email-keyed records into [uid] and updates profile doc.
  static Future<void> mergeLegacyEmailData(User user) async {
    final email = (user.email ?? '').trim();
    if (email.isEmpty) return;

    final usersRef = FirebaseFirestore.instance.collection('users');
    QuerySnapshot<Map<String, dynamic>> sameEmail;
    try {
      sameEmail = await usersRef.where('email', isEqualTo: email).get();
    } catch (_) {
      sameEmail = await usersRef
          .where(FieldPath.documentId, isEqualTo: user.uid)
          .get();
    }

    final merged = <String, dynamic>{
      'email': email,
      'userId': user.uid,
      'lastLoginAt': FieldValue.serverTimestamp(),
    };
    for (final doc in sameEmail.docs) {
      final data = doc.data();
      if ((data['username'] as String?)?.isNotEmpty == true) {
        merged['username'] = data['username'];
      }
      if ((data['photoBase64'] as String?)?.isNotEmpty == true) {
        merged['photoBase64'] = data['photoBase64'];
      }
      if ((data['photoUrl'] as String?)?.isNotEmpty == true) {
        merged['photoUrl'] = data['photoUrl'];
      }
    }
    await usersRef.doc(user.uid).set(merged, SetOptions(merge: true));

    for (final collection in const [
      'notes',
      'library',
      'custom_commands',
      'assessments',
    ]) {
      await _reassignOwner(
        collection: collection,
        fromUserId: email,
        toUserId: user.uid,
      );
    }
  }

  static Future<void> _reassignOwner({
    required String collection,
    required String fromUserId,
    required String toUserId,
  }) async {
    if (fromUserId == toUserId) return;
    QuerySnapshot<Map<String, dynamic>> snapshot;
    do {
      snapshot = await FirebaseFirestore.instance
          .collection(collection)
          .where('userId', isEqualTo: fromUserId)
          .limit(400)
          .get();
      if (snapshot.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'userId': toUserId});
      }
      await batch.commit();
    } while (snapshot.docs.length >= 400);
  }

  static Future<void> uploadGuestSessionData({
    required String uid,
    required TempNotesProvider notes,
    required TempLibraryProvider library,
  }) async {
    for (final note in notes.notes) {
      await FirebaseFirestore.instance.collection('notes').add({
        'userId': uid,
        'title': note.title,
        'content': note.content,
        if (note.audioUrl != null) 'audioUrl': note.audioUrl,
        if (note.audioPath != null) 'audioPath': note.audioPath,
        if (note.durationSeconds != null) 'durationSeconds': note.durationSeconds,
        'createdAt': Timestamp.fromDate(note.createdAt),
        'source': 'guest_upgrade',
      });
    }

    for (final item in library.items) {
      await FirebaseFirestore.instance.collection('library').add({
        'userId': uid,
        'fileName': item.fileName,
        'fileType': item.fileType,
        'content': item.content,
        if (item.highlights.isNotEmpty)
          'highlights': item.highlights.map((h) => h.toMap()).toList(),
        if (item.highlightStart != null) 'highlightStart': item.highlightStart,
        if (item.highlightEnd != null) 'highlightEnd': item.highlightEnd,
        'timestamp': FieldValue.serverTimestamp(),
        'source': 'guest_upgrade',
      });
    }

    notes.clear();
    library.clear();
  }

  static Future<void> applyCloudDataChoice({
    required User user,
    required bool syncCloudData,
    String? email,
  }) async {
    if (syncCloudData) {
      await mergeLegacyEmailData(user);
    } else {
      await EmailChangeService.clearCloudDataForUser(
        uid: user.uid,
        legacyEmail: email ?? user.email,
      );
    }
  }
}
