import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_credentials_service.dart';
import 'app_session.dart';

/// Email + password change with optional data sync or fresh start.
class EmailChangeService {
  EmailChangeService._();

  static const _ownerCollections = [
    'notes',
    'library',
    'custom_commands',
    'assessments',
  ];

  static Future<void> verifyCurrentCredentials({
    required String email,
    required String password,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'No signed-in account.',
      );
    }

    final trimmedEmail = email.trim();
    final accountEmail = user.email?.trim() ?? '';
    if (accountEmail.isNotEmpty &&
        trimmedEmail.toLowerCase() != accountEmail.toLowerCase()) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'That email does not match this account.',
      );
    }

    await AccountCredentialsService.reauthenticateWithPassword(user, password);
  }

  static Future<void> applyEmailChange({
    required String currentPassword,
    required String newEmail,
    required String newPassword,
    required bool syncData,
    required String oldEmail,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'No signed-in account.',
      );
    }

    await AccountCredentialsService.reauthenticateWithPassword(
      user,
      currentPassword,
    );

    final trimmedNew = newEmail.trim();
    if (!trimmedNew.contains('@') || !trimmedNew.contains('.')) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Invalid email address.',
      );
    }
    if (newPassword.length < 6) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'Password must be at least 6 characters.',
      );
    }

    final uid = user.uid;
    final trimmedOld = oldEmail.trim();

    if (syncData) {
      await _migrateEmailKeyedData(uid: uid, oldEmail: trimmedOld);
    } else {
      await _clearUserData(uid: uid, legacyEmail: trimmedOld);
    }

    // Firebase Auth 6+: email updates after the user opens the verification link.
    await user.verifyBeforeUpdateEmail(trimmedNew);
    await user.updatePassword(newPassword);
    await user.reload();

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'email': trimmedNew,
      'userId': uid,
      'lastLoginAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userEmail', trimmedNew);
    await AppSession.markSetupComplete(userId: uid);
  }

  static Future<void> _migrateEmailKeyedData({
    required String uid,
    required String oldEmail,
  }) async {
    if (oldEmail.isEmpty || oldEmail == uid) return;

    for (final collection in _ownerCollections) {
      await _reassignCollectionOwner(
        collection: collection,
        fromUserId: oldEmail,
        toUserId: uid,
      );
    }
  }

  /// Permanently removes cloud data for an account (used when declining sync).
  static Future<void> clearCloudDataForUser({
    required String uid,
    String? legacyEmail,
  }) =>
      _clearUserData(uid: uid, legacyEmail: legacyEmail);

  static Future<void> _clearUserData({
    required String uid,
    String? legacyEmail,
  }) async {
    final ownerIds = <String>{uid};
    if (legacyEmail != null && legacyEmail.isNotEmpty) {
      ownerIds.add(legacyEmail);
    }

    for (final ownerId in ownerIds) {
      for (final collection in _ownerCollections) {
        await _deleteWhereUserId(collection: collection, userId: ownerId);
      }
    }

    await _deleteSubcollection(
      userId: uid,
      subcollection: 'deleted_library',
    );
    await _deleteSubcollection(
      userId: uid,
      subcollection: 'saved_docs',
    );
  }

  static Future<void> _reassignCollectionOwner({
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

  static Future<void> _deleteWhereUserId({
    required String collection,
    required String userId,
  }) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;
    do {
      snapshot = await FirebaseFirestore.instance
          .collection(collection)
          .where('userId', isEqualTo: userId)
          .limit(400)
          .get();
      if (snapshot.docs.isEmpty) break;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } while (snapshot.docs.length >= 400);
  }

  static Future<void> _deleteSubcollection({
    required String userId,
    required String subcollection,
  }) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection(subcollection);

    QuerySnapshot<Map<String, dynamic>> snapshot;
    do {
      snapshot = await ref.limit(400).get();
      if (snapshot.docs.isEmpty) break;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } while (snapshot.docs.length >= 400);
  }
}
