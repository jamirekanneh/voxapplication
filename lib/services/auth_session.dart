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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGuestMode, false);
    await prefs.setBool(_keyHasProfile, true);
    await prefs.setString(_keyUserId, linked.userId);

    var email = linked.email?.trim() ?? '';
    var username = linked.username?.trim() ?? '';

    if (email.isEmpty || username.isEmpty) {
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
    await prefs.remove(_keyUserId);
    await prefs.remove('userEmail');
    await prefs.remove('userName');
  }

  static Future<void> clearGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGuestMode, false);
  }

  /// `true` → temp/local guest UI. Signed-in Firebase users are never guests.
  static Future<bool> shouldShowGuestUi([User? user]) async {
    user ??= FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) return false;
    return isExplicitGuestMode();
  }

  /// UID for Firestore queries; null when in guest mode.
  static Future<String?> effectiveUid([User? user]) async {
    user ??= FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) return user.uid;
    if (await shouldShowGuestUi(user)) return null;
    return savedUserId();
  }

  static Future<bool> isSignedIn([User? user]) async {
    user ??= FirebaseAuth.instance.currentUser;
    return user != null && !user.isAnonymous;
  }

  static Future<User?> waitForSignedInUser({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    var user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) return user;

    try {
      await for (final u in FirebaseAuth.instance.authStateChanges().timeout(
        timeout,
      )) {
        if (u != null && !u.isAnonymous) return u;
      }
    } catch (_) {}

    return FirebaseAuth.instance.currentUser?.isAnonymous == false
        ? FirebaseAuth.instance.currentUser
        : null;
  }
}
