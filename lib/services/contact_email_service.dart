import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emailjs/emailjs.dart' as emailjs;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

enum ContactDeliveryMethod { emailJs, firestore, mailtoPending, none }

/// Sends contact / feedback via EmailJS, with Firestore backup on mobile.
class ContactEmailService {
  ContactEmailService._();

  static String get _serviceId =>
      (dotenv.env['EMAILJS_SERVICE_ID'] ?? 'service_akm5fyg').trim();

  static String get _templateId =>
      (dotenv.env['EMAILJS_TEMPLATE_ID'] ?? 'template_ujtn37d').trim();

  static String get _publicKey =>
      (dotenv.env['EMAILJS_PUBLIC_KEY'] ?? '7lv-I2bSLiEeBpoYg').trim();

  static String get _privateKey =>
      (dotenv.env['EMAILJS_PRIVATE_KEY'] ?? '').trim();

  static String get supportEmail =>
      (dotenv.env['CONTACT_SUPPORT_EMAIL'] ?? 'jamiremkanneh@gmail.com').trim();

  static emailjs.Options get _options => emailjs.Options(
        publicKey: _publicKey,
        privateKey: _privateKey.isEmpty ? null : _privateKey,
      );

  static Future<ContactEmailSendResult> send({
    required Map<String, String> templateParams,
    required String mailtoSubject,
    required String mailtoBody,
    String source = 'app',
  }) async {
    final params = Map<String, String>.from(templateParams)
      ..putIfAbsent('to_email', () => supportEmail);

    if (_publicKey.isEmpty) {
      return _finishWithoutEmailJs(
        params: params,
        source: source,
        mailtoSubject: mailtoSubject,
        mailtoBody: mailtoBody,
        emailJsError: 'EmailJS public key is missing.',
      );
    }

    try {
      await emailjs.send(
        _serviceId,
        _templateId,
        params,
        _options,
      );
      return const ContactEmailSendResult(
        success: true,
        method: ContactDeliveryMethod.emailJs,
      );
    } catch (e, st) {
      debugPrint('EmailJS send failed: $e\n$st');
      return _finishWithoutEmailJs(
        params: params,
        source: source,
        mailtoSubject: mailtoSubject,
        mailtoBody: mailtoBody,
        emailJsError: e.toString(),
      );
    }
  }

  static Future<ContactEmailSendResult> _finishWithoutEmailJs({
    required Map<String, String> params,
    required String source,
    required String mailtoSubject,
    required String mailtoBody,
    required String emailJsError,
  }) async {
    final firestoreId = await _saveToFirestore(params, source: source);
    if (firestoreId != null) {
      return ContactEmailSendResult(
        success: true,
        method: ContactDeliveryMethod.firestore,
        firestoreId: firestoreId,
      );
    }

    final is403 = emailJsError.contains('403') ||
        emailJsError.toLowerCase().contains('non-browser');

    if (is403 && !kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return ContactEmailSendResult(
        success: false,
        method: ContactDeliveryMethod.none,
        errorMessage:
            'Messages could not be delivered from the app. In EmailJS go to '
            'Account → Security and enable "Allow EmailJS API for non-browser '
            'applications", then rebuild the app. Your message was not sent.',
      );
    }

    final mailto = await _tryMailto(mailtoSubject, mailtoBody);
    if (mailto) {
      return const ContactEmailSendResult(
        success: true,
        method: ContactDeliveryMethod.mailtoPending,
        pendingUserAction: true,
      );
    }

    if (is403) {
      return const ContactEmailSendResult(
        success: false,
        method: ContactDeliveryMethod.none,
        errorMessage:
            'Email could not be sent. Enable "Allow EmailJS API for '
            'non-browser applications" in your EmailJS dashboard '
            '(Account → Security), then rebuild the app.',
      );
    }

    return ContactEmailSendResult(
      success: false,
      method: ContactDeliveryMethod.none,
      errorMessage: _friendlyError(emailJsError),
    );
  }

  static Future<String?> _saveToFirestore(
    Map<String, String> params, {
    required String source,
  }) async {
    try {
      await _ensureFirebaseAuth();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final doc = await FirebaseFirestore.instance
          .collection('contact_messages')
          .add({
        'name': params['name'] ?? '',
        'email': params['email'] ?? '',
        'phone': params['message_phone'] ?? params['phone'] ?? '',
        'subject': params['subject'] ?? '',
        'message': params['message'] ?? '',
        'replyPreference': params['reply_preference'] ?? '',
        'title': params['title'] ?? '',
        'source': source,
        'supportEmail': supportEmail,
        'userId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('Contact message saved to Firestore: ${doc.id}');
      return doc.id;
    } catch (e, st) {
      debugPrint('Firestore contact save failed: $e\n$st');
      return null;
    }
  }

  static Future<void> _ensureFirebaseAuth() async {
    if (FirebaseAuth.instance.currentUser != null) return;
    await FirebaseAuth.instance.signInAnonymously();
  }

  static String _friendlyError(String raw) {
    if (raw.toLowerCase().contains('socket') ||
        raw.toLowerCase().contains('network')) {
      return 'Network error. Check your connection and try again.';
    }
    if (raw.length > 120) {
      return 'Failed to send message. Please try again.';
    }
    return 'Failed to send: $raw';
  }

  static Future<bool> _tryMailto(String subject, String body) async {
    try {
      final uri = Uri(
        scheme: 'mailto',
        path: supportEmail,
        queryParameters: <String, String>{
          'subject': subject,
          'body': body,
        },
      );
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e, st) {
      debugPrint('mailto fallback failed: $e\n$st');
      return false;
    }
  }
}

class ContactEmailSendResult {
  final bool success;
  final ContactDeliveryMethod method;
  final bool pendingUserAction;
  final String? firestoreId;
  final String? errorMessage;

  const ContactEmailSendResult({
    required this.success,
    this.method = ContactDeliveryMethod.none,
    this.pendingUserAction = false,
    this.firestoreId,
    this.errorMessage,
  });

  bool get usedMailtoFallback =>
      method == ContactDeliveryMethod.mailtoPending && pendingUserAction;
}

/// Plain-text WhatsApp body (UTF-8). WhatsApp supports *bold* and _italic_.
String buildContactWhatsAppMessage({
  required String name,
  required String email,
  required String phone,
  required String subject,
  required String message,
}) {
  return '\u{1F4E9} *New VOX App Message*\n\n'
      '\u{1F464} *Name:* $name\n'
      '\u{1F4E7} *Email:* $email\n'
      '\u{1F4DE} *Phone:* $phone\n'
      '\u{1F4CC} *Subject:* $subject\n\n'
      '\u{1F4AC} *Message:*\n$message\n\n'
      '\u{21A9}\u{FE0F} _Reply to this user via WhatsApp_';
}
