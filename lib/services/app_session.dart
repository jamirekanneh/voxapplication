import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session.dart';
import 'device_linked_user.dart';

enum LaunchDestination { home, profile }

/// Persists device + local flags so cold starts route correctly.
class AppSession {
  AppSession._();

  static const Duration _firestoreTimeout = Duration(seconds: 10);
  static const Duration _authTimeout = Duration(seconds: 12);

  /// Last user linked on this device (set when user signs in on this phone).
  static DeviceLinkedUser? lastRestoredDeviceUser;

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

  static Future<DeviceLinkedUser?> getDeviceLinkedUser() async {
    final id = await deviceId();
    if (id == null || id.isEmpty) return null;

    final doc = await _timeout(
      FirebaseFirestore.instance.collection('devices').doc(id).get(),
      _firestoreTimeout,
    );

    if (doc == null || !doc.exists) return null;

    final data = doc.data() ?? {};
    final uid = (data['lastUserId'] as String?)?.trim();
    if (uid == null || uid.isEmpty) return null;

    return DeviceLinkedUser(
      userId: uid,
      email: data['lastUserEmail'] as String?,
      username: data['lastUserName'] as String?,
    );
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

  /// Local prefs + device doc lookup. Prefer home when this phone was used before.
  static Future<LaunchDestination> resolveLaunchDestination() async {
    lastRestoredDeviceUser = null;

    if (await AuthSession.isExplicitGuestMode()) {
      return LaunchDestination.home;
    }

    // Fast path: prefs survive reinstall/cold start faster than Firebase Auth.
    final savedUid = await AuthSession.savedUserId();
    if (savedUid != null) {
      final linked = DeviceLinkedUser(userId: savedUid);
      await AuthSession.restoreFromDevice(linked);
      lastRestoredDeviceUser = linked;
      unawaited(
        AuthSession.waitForSignedInUser(timeout: _authTimeout).then((user) {
          if (user != null) markSetupComplete(userId: user.uid);
        }),
      );
      return LaunchDestination.home;
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('hasProfile') == true) {
      final uid = prefs.getString('userId')?.trim();
      if (uid != null && uid.isNotEmpty) {
        final linked = DeviceLinkedUser(userId: uid);
        await AuthSession.restoreFromDevice(linked);
        lastRestoredDeviceUser = linked;
        return LaunchDestination.home;
      }
    }

    // Device record in Firestore (same phone, prefs may have been cleared).
    final linked = await getDeviceLinkedUser();
    if (linked != null) {
      await AuthSession.restoreFromDevice(linked);
      lastRestoredDeviceUser = linked;
      unawaited(
        AuthSession.waitForSignedInUser(timeout: _authTimeout).then((user) {
          if (user != null) markSetupComplete(userId: user.uid);
        }),
      );
      return LaunchDestination.home;
    }

    final signedIn = await AuthSession.waitForSignedInUser(
      timeout: _authTimeout,
    );
    if (signedIn != null) {
      await markSetupComplete(userId: signedIn.uid);
      return LaunchDestination.home;
    }

    await registerFirstOpen();
    return LaunchDestination.profile;
  }

  /// Used when splash routing times out — never send known devices to profile.
  static Future<LaunchDestination> resolveLaunchFallback() async {
    if (await AuthSession.isExplicitGuestMode()) {
      return LaunchDestination.home;
    }
    final savedUid = await AuthSession.savedUserId();
    if (savedUid != null) {
      await AuthSession.restoreFromDevice(DeviceLinkedUser(userId: savedUid));
      lastRestoredDeviceUser = DeviceLinkedUser(userId: savedUid);
      return LaunchDestination.home;
    }
    final linked = await getDeviceLinkedUser();
    if (linked != null) {
      await AuthSession.restoreFromDevice(linked);
      lastRestoredDeviceUser = linked;
      return LaunchDestination.home;
    }
    return LaunchDestination.profile;
  }
}
