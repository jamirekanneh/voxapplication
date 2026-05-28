import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session.dart';

enum LaunchDestination { home, profile }

/// Persists device + local flags so cold starts route correctly.
class AppSession {
  AppSession._();

  static const Duration _firestoreTimeout = Duration(seconds: 4);
  static const Duration _authTimeout = Duration(seconds: 5);

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

  static Future<void> markSetupComplete({String? userId}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      await AuthSession.markSignedIn(user);
      userId = user.uid;
    } else if (await AuthSession.isExplicitGuestMode()) {
      await AuthSession.markGuestContinue();
    } else if (userId != null && userId.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasProfile', true);
      await prefs.setString('userId', userId);
    }

    final id = await deviceId();
    if (id == null || id.isEmpty) return;

    unawaited(
      _timeout(
        FirebaseFirestore.instance.collection('devices').doc(id).set(
          {
            'hasCompletedSetup': true,
            if (userId != null && userId.isNotEmpty) 'lastUserId': userId,
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

  static Future<LaunchDestination> resolveLaunchDestination() async {
    final signedIn = await AuthSession.waitForSignedInUser(
      timeout: _authTimeout,
    );
    if (signedIn != null) return LaunchDestination.home;

    if (await AuthSession.isExplicitGuestMode()) {
      return LaunchDestination.home;
    }

    final savedUid = await AuthSession.savedUserId();
    if (savedUid != null) {
      // Had an account before; ask to sign in again (do not show guest home).
      return LaunchDestination.profile;
    }

    await registerFirstOpen();
    return LaunchDestination.profile;
  }
}
