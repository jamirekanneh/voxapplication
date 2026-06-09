import 'package:emailjs/emailjs.dart' as emailjs;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sends contact / feedback email via EmailJS, with mailto fallback.
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
  }) async {
    if (_publicKey.isEmpty) {
      final mailto = await _tryMailto(mailtoSubject, mailtoBody);
      return mailto
          ? const ContactEmailSendResult(success: true, usedMailtoFallback: true)
          : const ContactEmailSendResult(
              success: false,
              errorMessage: 'Email is not configured on this build.',
            );
    }

    try {
      await emailjs.send(
        _serviceId,
        _templateId,
        templateParams,
        _options,
      );
      return const ContactEmailSendResult(success: true);
    } catch (e, st) {
      debugPrint('EmailJS send failed: $e\n$st');

      final message = e.toString();
      final is403 = message.contains('403') ||
          message.toLowerCase().contains('private key') ||
          message.toLowerCase().contains('non-browser');

      final mailto = await _tryMailto(mailtoSubject, mailtoBody);
      if (mailto) {
        return const ContactEmailSendResult(
          success: true,
          usedMailtoFallback: true,
        );
      }

      if (is403) {
        return const ContactEmailSendResult(
          success: false,
          errorMessage:
              'Email could not be sent from the app. Add EMAILJS_PRIVATE_KEY '
              'to assets/project.env and rebuild, or enable '
              '"Allow EmailJS API for non-browser applications" in your '
              'EmailJS dashboard (Account → Security).',
        );
      }

      return ContactEmailSendResult(
        success: false,
        errorMessage: _friendlyError(message),
      );
    }
  }

  static String _friendlyError(String raw) {
    if (raw.toLowerCase().contains('socket') ||
        raw.toLowerCase().contains('network')) {
      return 'Network error. Check your connection and try again.';
    }
    if (raw.length > 120) {
      return 'Failed to send email. Please try again.';
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
  final bool usedMailtoFallback;
  final String? errorMessage;

  const ContactEmailSendResult({
    required this.success,
    this.usedMailtoFallback = false,
    this.errorMessage,
  });
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
