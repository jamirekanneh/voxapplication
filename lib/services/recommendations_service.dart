import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class RecommendationSaveResult {
  final bool success;
  final String? documentId;
  final String? errorMessage;

  const RecommendationSaveResult({
    required this.success,
    this.documentId,
    this.errorMessage,
  });
}

/// Stores Play Store–style ratings and feedback for developers to review later.
class RecommendationsService {
  RecommendationsService._();

  static Future<RecommendationSaveResult> submit({
    required int rating,
    required String message,
  }) async {
    if (rating < 0 || rating > 5) {
      return const RecommendationSaveResult(
        success: false,
        errorMessage: 'Please select a star rating.',
      );
    }

    final trimmed = message.trim();
    if (rating == 0 && trimmed.isEmpty) {
      return const RecommendationSaveResult(
        success: false,
        errorMessage: 'Add a rating or write a short message.',
      );
    }

    try {
      await _ensureFirebaseAuth();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return const RecommendationSaveResult(
          success: false,
          errorMessage: 'Could not save your feedback. Please try again.',
        );
      }

      final doc = await FirebaseFirestore.instance.collection('recommendations').add({
        'rating': rating,
        'message': trimmed,
        'userId': user.uid,
        'published': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Recommendation saved: ${doc.id}');
      return RecommendationSaveResult(success: true, documentId: doc.id);
    } catch (e, st) {
      debugPrint('Recommendation save failed: $e\n$st');
      return const RecommendationSaveResult(
        success: false,
        errorMessage: 'Failed to save. Check your connection and try again.',
      );
    }
  }

  static Future<void> _ensureFirebaseAuth() async {
    if (FirebaseAuth.instance.currentUser != null) return;
    await FirebaseAuth.instance.signInAnonymously();
  }
}
