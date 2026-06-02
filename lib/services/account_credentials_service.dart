import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Web client ID from Firebase (client_type 3) — required for Google re-auth on Android.
const kGoogleServerClientId =
    '1033671503358-c8dhmiu6henkq7ig0cg8ata4mq24a9af.apps.googleusercontent.com';

/// Firebase Auth flows for changing email / password (with reauthentication).
class AccountCredentialsService {
  AccountCredentialsService._();

  static bool hasPasswordProvider(User? user) {
    return user?.providerData.any(
          (p) => p.providerId == EmailAuthProvider.PROVIDER_ID,
        ) ??
        false;
  }

  static bool hasGoogleProvider(User? user) {
    return user?.providerData.any(
          (p) => p.providerId == GoogleAuthProvider.PROVIDER_ID,
        ) ??
        false;
  }

  static String describeProviders(User? user) {
    if (user == null) return '';
    final parts = <String>[];
    if (hasPasswordProvider(user)) parts.add('Email & password');
    if (hasGoogleProvider(user)) parts.add('Google');
    return parts.join(' · ');
  }

  static String authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'That email is already used by another account.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect password. Try again.';
      case 'requires-recent-login':
        return 'For security, confirm your identity and try again.';
      case 'user-mismatch':
        return 'Sign-in did not match this account. Try again.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection.';
      default:
        final msg = (e.message ?? '').trim();
        return msg.isNotEmpty ? msg : e.code;
    }
  }

  static Future<void> reauthenticateWithPassword(
    User user,
    String password,
  ) async {
    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-email',
        message: 'No email on this account.',
      );
    }
    final cred = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    await user.reauthenticateWithCredential(cred);
  }

  static Future<void> reauthenticateWithGoogle(User user) async {
    if (kIsWeb) {
      await user.reauthenticateWithProvider(GoogleAuthProvider());
      return;
    }

    GoogleSignIn.instance.initialize(serverClientId: kGoogleServerClientId);
    final googleUser = await GoogleSignIn.instance.authenticate();
    final idToken = googleUser.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'google-token-missing',
        message: 'Google sign-in did not return a token.',
      );
    }
    final cred = GoogleAuthProvider.credential(idToken: idToken);
    await user.reauthenticateWithCredential(cred);
  }

  static Future<void> changePassword({
    required User user,
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < 6) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'Password must be at least 6 characters.',
      );
    }
    await reauthenticateWithPassword(user, currentPassword);
    await user.updatePassword(newPassword);
  }

  static Future<void> changePasswordAfterGoogleReauth({
    required User user,
    required String newPassword,
  }) async {
    if (newPassword.length < 6) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'Password must be at least 6 characters.',
      );
    }
    await reauthenticateWithGoogle(user);
    await user.updatePassword(newPassword);
  }

  /// Sends Firebase verification email; account email updates after user confirms.
  static Future<void> requestEmailChange({
    required User user,
    required String newEmail,
    String? currentPassword,
    bool useGoogleReauth = false,
  }) async {
    final trimmed = newEmail.trim();
    if (!trimmed.contains('@') || !trimmed.contains('.')) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Invalid email address.',
      );
    }

    if (useGoogleReauth || (!hasPasswordProvider(user) && hasGoogleProvider(user))) {
      await reauthenticateWithGoogle(user);
    } else if (currentPassword != null && currentPassword.isNotEmpty) {
      await reauthenticateWithPassword(user, currentPassword);
    } else {
      throw FirebaseAuthException(
        code: 'requires-recent-login',
        message: 'Confirm your current password or Google account.',
      );
    }

    await user.verifyBeforeUpdateEmail(trimmed);
  }

  static Future<void> sendPasswordResetEmail(String email) async {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
  }
}
