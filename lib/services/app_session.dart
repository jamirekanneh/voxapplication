import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session.dart';
import 'auth_restore.dart';
import 'device_linked_user.dart';

enum LaunchDestination { home, profile }

/// Persists device + local flags so cold starts route correctly.
class AppSession {
  AppSession._();

  static const Duration _firestoreTimeout = Duration(seconds: 10);
  static const Duration _authTimeout = Duration(seconds: 12);
  /// Max wait on splash — full auth restore continues in the background.
  static const Duration splashAuthTimeout = Duration(seconds: 5);

  /// Last user linked on this device (set when device is recognized).
  static DeviceLinkedUser? lastRestoredDeviceUser;

  /// Firebase Auth matches the device-linked user (required for Firestore reads).
  static bool get firestoreReadyForDevice {
    final linked = lastRestoredDeviceUser;
    if (linked == null) return false;
    return AuthSession.canQueryFirestore(linked.userId);
  }

  /// UID ready immediately after splash bootstrap — avoids list flash/spinner.
  static String? get bootstrapUid {
    final linked = lastRestoredDeviceUser;
    if (linked != null && linked.userId.isNotEmpty) {
      return linked.userId;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) return user.uid;
    return null;
  }

  static Future<T?> _timeout<T>(
    Future<T?> future,
    Duration duration, {
    T? fallback,
  }) async {
    try {
      return await future.timeout(duration);
    } on TimeoutException catch (e) {
      debugPrint('AppSession timeout: $e');
      return fallback;
    } catch (e) {
      debugPrint('AppSession error: $e');
      return fallback;
    }
  }

  static Future<String?> deviceId() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      var webId = prefs.getString('chrome_mock_device_id');
      if (webId == null) {
        webId = 'chrome_user_${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString('chrome_mock_device_id', webId);
      }
      return webId;
    }

    final deviceInfo = DeviceInfoPlugin();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return (await deviceInfo.androidInfo).id;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return (await deviceInfo.iosInfo).identifierForVendor;
      }
    } catch (e) {
      debugPrint('AppSession deviceId error: $e');
    }
    return null;
  }

  static Future<DeviceLinkedUser?> getDeviceLinkedUser({int attempts = 3}) async {
    final id = await deviceId();
    if (id == null || id.isEmpty) return null;

    for (var i = 0; i < attempts; i++) {
      final doc = await _timeout(
        FirebaseFirestore.instance.collection('devices').doc(id).get(),
        _firestoreTimeout,
      );

      if (doc != null && doc.exists) {
        final data = doc.data() ?? {};
        final uid = (data['lastUserId'] as String?)?.trim();
        if (uid != null && uid.isNotEmpty) {
          return DeviceLinkedUser(
            userId: uid,
            email: (data['lastUserEmail'] as String?)?.trim(),
            username: (data['lastUserName'] as String?)?.trim(),
          );
        }
        return null;
      }

      if (i < attempts - 1) {
        await Future<void>.delayed(Duration(milliseconds: 350 * (i + 1)));
      }
    }
    return null;
  }

  /// True when this phone is linked to an account (device doc or saved prefs).
  static Future<bool> isDeviceRecognized() async {
    if (await AuthSession.isExplicitGuestMode()) return false;
    if (await AuthSession.savedUserId() != null) return true;
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('userId')?.trim();
    if ((prefs.getBool('hasProfile') ?? false) &&
        uid != null &&
        uid.isNotEmpty) {
      return true;
    }
    final linked = await getDeviceLinkedUser(attempts: 2);
    return linked != null;
  }

  /// Loads username + email from device doc, prefs, and `users/{uid}` when auth allows.
  static Future<DeviceLinkedUser> enrichLinkedUser(DeviceLinkedUser linked) async {
    var username = linked.username?.trim() ?? '';
    var email = linked.email?.trim() ?? '';

    final prefs = await SharedPreferences.getInstance();
    if (username.isEmpty) {
      username = prefs.getString('userName')?.trim() ?? '';
    }
    if (email.isEmpty) {
      email = prefs.getString('userEmail')?.trim() ?? '';
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.uid == linked.userId) {
      if (username.isEmpty && (user.displayName?.isNotEmpty ?? false)) {
        username = user.displayName!.trim();
      }
      if (email.isEmpty && (user.email?.isNotEmpty ?? false)) {
        email = user.email!.trim();
      }
      try {
        final doc = await _timeout(
          FirebaseFirestore.instance.collection('users').doc(linked.userId).get(),
          _firestoreTimeout,
        );
        if (doc != null && doc.exists) {
          final data = doc.data() ?? {};
          if (username.isEmpty) {
            username = (data['username'] as String? ?? '').trim();
          }
          if (email.isEmpty) {
            email = (data['email'] as String? ?? '').trim();
          }
        }
      } catch (e) {
        debugPrint('AppSession enrichLinkedUser: $e');
      }
    }

    return DeviceLinkedUser(
      userId: linked.userId,
      email: email.isEmpty ? null : email,
      username: username.isEmpty ? null : username,
    );
  }

  /// Device ID → userId + name/email in prefs; sync `devices` doc; restore auth silently.
  static Future<DeviceLinkedUser?> recognizeAndPrepareDevice({
    Duration authTimeout = _authTimeout,
  }) async {
    if (await AuthSession.isExplicitGuestMode()) return null;

    DeviceLinkedUser? linked = await getDeviceLinkedUser(attempts: 3);
    final savedUid = await AuthSession.savedUserId();
    if (linked == null && savedUid != null) {
      linked = DeviceLinkedUser(userId: savedUid);
    }
    if (linked == null) {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('userId')?.trim();
      if ((prefs.getBool('hasProfile') ?? false) &&
          uid != null &&
          uid.isNotEmpty) {
        linked = DeviceLinkedUser(userId: uid);
      }
    }
    if (linked == null) return null;

    linked = await enrichLinkedUser(linked);
    await AuthSession.restoreFromDevice(linked);
    lastRestoredDeviceUser = linked;

    await AuthSession.clearConflictingAuthSession();
    await AuthSession.waitForAuthReady(timeout: authTimeout);
    await AuthRestore.restoreForSavedUser(
      linked.userId,
      timeout: authTimeout,
    );

    linked = await enrichLinkedUser(linked);
    await AuthSession.restoreFromDevice(linked);
    lastRestoredDeviceUser = linked;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      await AuthSession.markSignedIn(user);
    }

    await markSetupComplete(userId: linked.userId);
    debugPrint(
      'AppSession: device recognized uid=${linked.userId} '
      'name=${linked.username} email=${linked.email}',
    );
    return linked;
  }

  /// Display name for welcome snackbar after device recognition.
  static Future<String?> welcomeDisplayName() async {
    final linked = lastRestoredDeviceUser;
    if (linked?.username?.isNotEmpty ?? false) return linked!.username;

    final prefs = await SharedPreferences.getInstance();
    final fromPrefs = prefs.getString('userName')?.trim();
    if (fromPrefs != null && fromPrefs.isNotEmpty) return fromPrefs;

    final user = FirebaseAuth.instance.currentUser;
    final fromAuth = user?.displayName?.trim();
    if (fromAuth != null && fromAuth.isNotEmpty) return fromAuth;

    return null;
  }

  /// Restore prefs from device/saved UID, then wait for Firebase Auth persistence.
  static Future<bool> restoreLocalAndAwaitAuth({
    required DeviceLinkedUser linked,
    Duration authWait = const Duration(seconds: 12),
  }) async {
    final enriched = await enrichLinkedUser(linked);
    await AuthSession.restoreFromDevice(enriched);
    lastRestoredDeviceUser = enriched;
    await AuthSession.clearConflictingAuthSession();
    await AuthSession.waitForAuthReady(timeout: authWait);
    var user = FirebaseAuth.instance.currentUser;
    if (user != null && user.isAnonymous && user.uid == enriched.userId) {
      return true;
    }
    if (user != null && !user.isAnonymous) {
      await AuthSession.markSignedIn(user);
      await markSetupComplete(userId: user.uid);
      return true;
    }
    return false;
  }

  static Future<void> markSetupComplete({String? userId}) async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    String? email;
    String? username;

    if (user != null && !user.isAnonymous) {
      await AuthSession.markSignedIn(user);
      userId = user.uid;
      email = user.email;
      username = user.displayName;
    } else if (await AuthSession.isExplicitGuestMode()) {
      await AuthSession.markGuestContinue();
      userId = null;
    } else if (userId != null && userId.isNotEmpty) {
      await prefs.setBool('hasProfile', true);
      await prefs.setString('userId', userId);
      email = prefs.getString('userEmail');
      username = prefs.getString('userName');
    }

    final linked = lastRestoredDeviceUser;
    if (linked != null && linked.userId == userId) {
      if ((username == null || username.isEmpty) &&
          linked.username?.isNotEmpty == true) {
        username = linked.username;
      }
      if ((email == null || email.isEmpty) && linked.email?.isNotEmpty == true) {
        email = linked.email;
      }
    }

    final id = await deviceId();
    if (id == null || id.isEmpty) return;

    unawaited(
      _timeout(
        FirebaseFirestore.instance.collection('devices').doc(id).set(
          {
            'hasCompletedSetup': true,
            if (userId != null && userId.isNotEmpty) 'lastUserId': userId,
            if (email != null && email.isNotEmpty) 'lastUserEmail': email,
            if (username != null && username.isNotEmpty) 'lastUserName': username,
            'lastOpenedAt': FieldValue.serverTimestamp(),
            'platform': kIsWeb ? 'Web' : defaultTargetPlatform.toString(),
          },
          SetOptions(merge: true),
        ),
        _firestoreTimeout,
      ),
    );
  }

  static Future<void> registerFirstOpen() async {
    final id = await deviceId();
    if (id == null || id.isEmpty) return;

    unawaited(
      _timeout(
        FirebaseFirestore.instance.collection('devices').doc(id).set(
          {
            'firstOpenedAt': FieldValue.serverTimestamp(),
            'platform': kIsWeb ? 'Web' : defaultTargetPlatform.toString(),
          },
          SetOptions(merge: true),
        ),
        _firestoreTimeout,
      ),
    );
  }

  /// Returning phone → Home. New phone → Profile setup only.
  static Future<LaunchDestination> resolveLaunchDestination() async {
    if (await AuthSession.isExplicitGuestMode()) {
      return LaunchDestination.home;
    }

    // 1. Device registry + prefs (primary path for returning users).
    final prepared = await recognizeAndPrepareDevice(
      authTimeout: splashAuthTimeout,
    );
    if (prepared != null) {
      return LaunchDestination.home;
    }

    // 2. Firebase Auth session already restored.
    await AuthSession.waitForAuthReady(timeout: splashAuthTimeout);
    var user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      await AuthSession.markSignedIn(user);
      await markSetupComplete(userId: user.uid);
      lastRestoredDeviceUser = DeviceLinkedUser(
        userId: user.uid,
        email: user.email,
        username: user.displayName,
      );
      return LaunchDestination.home;
    }

    user = await AuthSession.waitForSignedInUser(timeout: splashAuthTimeout);
    if (user != null && !user.isAnonymous) {
      await markSetupComplete(userId: user.uid);
      lastRestoredDeviceUser = DeviceLinkedUser(
        userId: user.uid,
        email: user.email,
        username: user.displayName,
      );
      return LaunchDestination.home;
    }

    await registerFirstOpen();
    return LaunchDestination.profile;
  }

  /// Splash timeout fallback — never send a known device to profile.
  static Future<LaunchDestination> resolveLaunchFallback() async {
    if (await AuthSession.isExplicitGuestMode()) {
      return LaunchDestination.home;
    }

    final prepared = await recognizeAndPrepareDevice();
    if (prepared != null) return LaunchDestination.home;

    await AuthSession.waitForAuthReady(timeout: const Duration(seconds: 5));
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      await AuthSession.markSignedIn(user);
      return LaunchDestination.home;
    }

    if (await AuthSession.savedUserId() != null) {
      return LaunchDestination.home;
    }

    final linked = await getDeviceLinkedUser(attempts: 2);
    if (linked != null) {
      await AuthSession.restoreFromDevice(linked);
      lastRestoredDeviceUser = linked;
      return LaunchDestination.home;
    }

    return LaunchDestination.profile;
  }
}
