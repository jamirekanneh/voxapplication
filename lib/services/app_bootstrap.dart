import 'dart:async';

import 'package:flutter/foundation.dart';

import '../analytics_service.dart';
import '../notification_service.dart';
import 'auth_session.dart';
import 'auth_restore.dart';
import 'reminders_service.dart';
import 'transcription_queue.dart';

/// Startup work split so splash can finish quickly.
class AppBootstrap {
  AppBootstrap._();

  static bool _deferredDone = false;
  static bool _deferredRunning = false;

  /// Non-blocking follow-up after the first screen is shown.
  static void runDeferred() {
    if (_deferredDone || _deferredRunning) return;
    _deferredRunning = true;
    unawaited(_runDeferred());
  }

  static Future<void> _runDeferred() async {
    try {
      if (!await AuthSession.isExplicitGuestMode()) {
        final saved = await AuthSession.savedUserId();
        if (saved != null && !AuthSession.canQueryFirestore(saved)) {
          await AuthRestore.restoreForSavedUser(
            saved,
            timeout: const Duration(seconds: 20),
          );
        }
      }

      await AnalyticsService.instance.load();
      await AnalyticsService.instance.recordAppOpen();

      await NotificationService.instance.init();
      try {
        await NotificationService.instance.scheduleDailyReminder(20, 0);
        await RemindersService.instance.rescheduleAll();
      } catch (e) {
        debugPrint('AppBootstrap: reminders: $e');
      }

      AnalyticsService.instance.autoSyncIfNeeded();
      await TranscriptionQueue.instance.init();
    } catch (e, st) {
      debugPrint('AppBootstrap error: $e\n$st');
    } finally {
      _deferredDone = true;
      _deferredRunning = false;
    }
  }
}
