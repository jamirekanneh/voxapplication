import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Inbox for Contact Us form submissions (EmailJS + Firestore backup).
const String kContactSupportEmail = 'jamiremkanneh@gmail.com';

class ContactInboxResult {
  final bool success;
  final String? documentId;
  final String? errorMessage;

  const ContactInboxResult({
    required this.success,
    this.documentId,
    this.errorMessage,
  });
}

/// Saves Contact Us submissions to Firestore; a Cloud Function emails the team.
class ContactInboxService {
  ContactInboxService._();

  static String get supportEmail => kContactSupportEmail;

  static Future<ContactInboxResult> submit({
    required String name,
    required String email,
    required String phone,
    required String subject,
    required String message,
    required String replyPreference,
    String source = 'contact_us',
  }) async {
    final trimmedName = name.trim();
    final trimmedEmail = email.trim();
    final trimmedSubject = subject.trim();
    final trimmedMessage = message.trim();

    if (trimmedName.isEmpty ||
        trimmedEmail.isEmpty ||
        trimmedSubject.isEmpty ||
        trimmedMessage.isEmpty) {
      return const ContactInboxResult(
        success: false,
        errorMessage: 'Please fill in all required fields.',
      );
    }

    try {
      await _ensureFirebaseAuth();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return const ContactInboxResult(
          success: false,
          errorMessage: 'Could not send your message. Please try again.',
        );
      }

      final doc = await FirebaseFirestore.instance.collection('contact_messages').add({
        'name': trimmedName,
        'email': trimmedEmail,
        'phone': phone.trim(),
        'subject': trimmedSubject,
        'message': trimmedMessage,
        'replyPreference': replyPreference,
        'title': 'New message from VOX App',
        'source': source,
        'supportEmail': supportEmail,
        'userId': user.uid,
        'emailDeliveryStatus': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Contact message queued: ${doc.id}');
      return ContactInboxResult(success: true, documentId: doc.id);
    } catch (e, st) {
      debugPrint('Contact inbox save failed: $e\n$st');
      return const ContactInboxResult(
        success: false,
        errorMessage: 'Failed to send. Check your connection and try again.',
      );
    }
  }

  static Future<void> _ensureFirebaseAuth() async {
    if (FirebaseAuth.instance.currentUser != null) return;
    await FirebaseAuth.instance.signInAnonymously();
  }
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
