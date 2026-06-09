import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_linked_user.dart';

/// Distinguishes explicit guest mode from a signed-in Firebase user.
class AuthSession {
  AuthSession._();

  static const _keyGuestMode = 'explicitGuestMode';
  static const _keyUserId = 'userId';
  static const _keyHasProfile = 'hasProfile';
  static const _keyPendingSignIn = 'pendingSignInAfterLogout';

  /// Set on logout — blocks auto device restore and silent Google until sign-in or guest.
  static Future<bool> isPendingSignIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyPendingSignIn) ?? false;
  }

  static Future<void> markPendingSignIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPendingSignIn, true);
  }

  static Future<void> clearPendingSignIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPendingSignIn);
  }

  static Future<bool> isExplicitGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyGuestMode) ?? false;
  }

  static Future<String?> savedUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_keyUserId)?.trim();
    return (id != null && id.isNotEmpty) ? id : null;
  }

  static Future<void> markSignedIn(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGuestMode, false);
    await prefs.setBool(_keyHasProfile, true);
    await prefs.remove(_keyPendingSignIn);
    await prefs.setString(_keyUserId, user.uid);
    if (user.email?.isNotEmpty ?? false) {
      await prefs.setString('userEmail', user.email!);
    }
    if (user.displayName?.isNotEmpty ?? false) {
      await prefs.setString('userName', user.displayName!);
    }
  }

  /// Restores local session from a device-linked account (Firestore data by UID).
  static Future<void> restoreFromDevice(DeviceLinkedUser linked) async {
    if (await isPendingSignIn()) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGuestMode, false);
    await prefs.setBool(_keyHasProfile, true);
    await prefs.setString(_keyUserId, linked.userId);

    var email = linked.email?.trim() ?? '';
    var username = linked.username?.trim() ?? '';

    final authedUser = FirebaseAuth.instance.currentUser;
    final canReadProfile = authedUser != null &&
        !authedUser.isAnonymous &&
        authedUser.uid == linked.userId;
    if (canReadProfile && (email.isEmpty || username.isEmpty)) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(linked.userId)
            .get();
        if (doc.exists) {
          final data = doc.data() ?? {};
          if (username.isEmpty) {
            username = (data['username'] as String? ?? '').trim();
          }
          if (email.isEmpty) {
            email = (data['email'] as String? ?? '').trim();
          }
        }
      } catch (e) {
        debugPrint('restoreFromDevice profile load: $e');
      }
    }

    if (email.isNotEmpty) await prefs.setString('userEmail', email);
    if (username.isNotEmpty) await prefs.setString('userName', username);
  }

  static Future<void> markGuestContinue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGuestMode, true);
    await prefs.setBool(_keyHasProfile, true);
    await prefs.remove(_keyPendingSignIn);
    await prefs.remove(_keyUserId);
    await prefs.remove('userEmail');
    await prefs.remove('userName');
  }

  static Future<void> clearGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGuestMode, false);
  }

  /// Guest UI (temp storage, GUEST badges) — only after "Continue Anyway".
  static Future<bool> usesGuestExperience() => isExplicitGuestMode();

  /// This device is linked to a registered account (not explicit guest).
  static Future<bool> hasDeviceLinkedAccount() async {
    if (await isExplicitGuestMode()) return false;
    final saved = await savedUserId();
    if (saved != null) return true;
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_keyUserId)?.trim();
    return (prefs.getBool(_keyHasProfile) ?? false) &&
        uid != null &&
        uid.isNotEmpty;
  }

  /// `true` → temp/local guest UI. Only explicit guest mode counts.
  static Future<bool> shouldShowGuestUi([User? user]) async {
    return usesGuestExperience();
  }

  /// True when Firestore rules allow reads for documents owned by [uid].
  static bool canQueryFirestore(String uid) {
    final user = FirebaseAuth.instance.currentUser;
    return user != null && user.uid == uid;
  }

  /// Waits until Firebase Auth session matches the device-linked [uid].
  static Future<bool> waitForAuthMatchingUid(
    String uid, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (canQueryFirestore(uid)) return true;

    await clearConflictingAuthSession();
    if (canQueryFirestore(uid)) return true;

    try {
      await FirebaseAuth.instance.authStateChanges().firstWhere(
        (u) => u != null && u.uid == uid,
      ).timeout(timeout);
    } on TimeoutException {
      debugPrint('AuthSession: auth wait timed out for uid=$uid');
    } catch (e) {
      debugPrint('AuthSession: auth wait error: $e');
    }

    if (canQueryFirestore(uid)) {
      try {
        await FirebaseAuth.instance.currentUser?.reload();
      } catch (_) {}
      return true;
    }
    return false;
  }

  static Future<bool> waitForAuthMatchingSavedUser({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final saved = await savedUserId();
    if (saved == null) return false;
    return waitForAuthMatchingUid(saved, timeout: timeout);
  }

  /// Guest flag + device [userId]. [dataReady] = Firebase Auth matches (can load Firestore).
  static Future<({bool guest, String? uid, bool dataReady})> resolveForApp({
    Duration authTimeout = const Duration(seconds: 15),
  }) async {
    if (await usesGuestExperience()) {
      return (guest: true, uid: null, dataReady: false);
    }

    final saved = await savedUserId();
    if (saved != null) {
      var ready = canQueryFirestore(saved);
      if (!ready) {
        ready = await waitForAuthMatchingUid(saved, timeout: authTimeout);
      }
      return (guest: false, uid: saved, dataReady: ready);
    }

    final uid = await awaitAuthenticatedUid(timeout: authTimeout);
    final ready = uid != null && canQueryFirestore(uid);
    return (guest: false, uid: uid, dataReady: ready);
  }

  /// UID for Firestore — device-linked users use persisted [userId] immediately.
  static Future<String?> effectiveUid([User? user]) async {
    if (await shouldShowGuestUi(user)) return null;

    user ??= FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) return user.uid;

    final saved = await savedUserId();
    if (saved == null) return null;

    final current = FirebaseAuth.instance.currentUser;
    if (current != null && current.uid == saved) return saved;

    return saved;
  }

  /// Signs out any Firebase session whose uid differs from the device-linked account.
  static Future<void> clearConflictingAuthSession() async {
    if (await isExplicitGuestMode()) return;
    final saved = await savedUserId();
    if (saved == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid == saved) return;

    try {
      await FirebaseAuth.instance.signOut();
      debugPrint(
        'AuthSession: cleared conflicting session (uid ${user.uid} != saved $saved).',
      );
    } catch (e) {
      debugPrint('AuthSession signOut error: $e');
    }
  }

  @Deprecated('Use clearConflictingAuthSession')
  static Future<void> clearStaleAnonymousSession() =>
      clearConflictingAuthSession();

  /// Waits for Firebase Auth to restore. Returns uid only when auth matches saved device user.
  static Future<String?> awaitAuthenticatedUid({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (await shouldShowGuestUi()) return null;

    final saved = await savedUserId();
    if (saved == null) return null;

    if (canQueryFirestore(saved)) return saved;

    await clearConflictingAuthSession();
    await waitForAuthReady(timeout: timeout);
    if (canQueryFirestore(saved)) return saved;

    await waitForSignedInUser(timeout: timeout);
    if (canQueryFirestore(saved)) return saved;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.uid == saved) return saved;

    debugPrint(
      'AuthSession: saved uid=$saved but Firebase Auth not restored (current=${user?.uid}).',
    );
    return null;
  }

  /// Waits for Firebase Auth to emit its initial persisted session (cold start).
  static Future<void> waitForAuthReady({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final existing = FirebaseAuth.instance.currentUser;
    if (existing != null) return;

    try {
      await FirebaseAuth.instance.authStateChanges().firstWhere(
        (u) => u != null,
      ).timeout(timeout);
    } on TimeoutException {
      // Caller uses saved device userId.
    } catch (_) {}
  }

  static Future<bool> isSignedIn([User? user]) async {
    user ??= FirebaseAuth.instance.currentUser;
    return user != null && !user.isAnonymous;
  }

  static Future<User?> waitForSignedInUser({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    var user = FirebaseAuth.instance.currentUser;
    if (user != null) return user;

    try {
      await for (final u in FirebaseAuth.instance.authStateChanges().timeout(
        timeout,
      )) {
        if (u != null) return u;
      }
    } catch (_) {}

    return FirebaseAuth.instance.currentUser;
  }
}
