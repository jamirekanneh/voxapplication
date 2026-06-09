import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_session.dart';

/// Web client ID from Firebase (client_type 3) — required for idToken on Android.
const _kGoogleServerClientId =
    '1033671503358-c8dhmiu6henkq7ig0cg8ata4mq24a9af.apps.googleusercontent.com';

/// Restores a Firebase Auth session that matches the device-linked [expectedUid].
class AuthRestore {
  AuthRestore._();

  static Future<bool> restoreForSavedUser(
    String expectedUid, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (expectedUid.isEmpty) return false;
    if (await AuthSession.isPendingSignIn()) return false;

    await AuthSession.clearConflictingAuthSession();
    if (AuthSession.canQueryFirestore(expectedUid)) return true;

    await AuthSession.waitForAuthReady(
      timeout: Duration(seconds: timeout.inSeconds.clamp(4, 12)),
    );
    if (AuthSession.canQueryFirestore(expectedUid)) return true;

    if (!kIsWeb) {
      final googleOk = await _trySilentGoogle(expectedUid);
      if (googleOk) return true;
    }

    return AuthSession.waitForAuthMatchingUid(expectedUid, timeout: timeout);
  }

  static Future<bool> _trySilentGoogle(String expectedUid) async {
    if (await AuthSession.isPendingSignIn()) return false;
    try {
      GoogleSignIn.instance.initialize(serverClientId: _kGoogleServerClientId);
      final googleUser =
          await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (googleUser == null) return false;

      final idToken = googleUser.authentication.idToken;
      if (idToken == null || idToken.isEmpty) return false;

      final result = await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      final user = result.user;
      if (user != null && user.uid == expectedUid) {
        await AuthSession.markSignedIn(user);
        return true;
      }
      if (user != null && user.uid != expectedUid) {
        await FirebaseAuth.instance.signOut();
      }
    } catch (e) {
      debugPrint('AuthRestore silent Google: $e');
    }
    return false;
  }
}
