import 'package:flutter/foundation.dart';

import '../analytics_service.dart';
import '../notification_service.dart';
import 'auth_session.dart';
import 'auth_restore.dart';
import 'app_session.dart';
import 'reminders_service.dart';
import 'transcription_queue.dart';

/// Heavy startup work — run while the Flutter splash UI is visible.
class AppBootstrap {
  AppBootstrap._();

  static bool _done = false;

  static Future<void> run() async {
    if (_done) return;
    try {
      if (!await AuthSession.isExplicitGuestMode()) {
        await AppSession.recognizeAndPrepareDevice();
        final saved = await AuthSession.savedUserId();
        if (saved != null) {
          await AuthRestore.restoreForSavedUser(
            saved,
            timeout: const Duration(seconds: 30),
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
      _done = true;
    }
  }
}
