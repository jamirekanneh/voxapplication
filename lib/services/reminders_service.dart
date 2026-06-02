import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/study_reminder.dart';
import '../notification_service.dart';

class RemindersService {
  RemindersService._();
  static final RemindersService instance = RemindersService._();

  static const _storageKey = 'study_reminders_v1';

  static int notificationIdFor(String reminderId) =>
      reminderId.hashCode & 0x7FFFFFFF;

  Future<List<StudyReminder>> loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(StudyReminder.fromJson)
          .toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<StudyReminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(reminders.map((r) => r.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  Future<StudyReminder> addReminder({
    required String targetId,
    required String targetTitle,
    required StudyReminderTargetType targetType,
    required DateTime scheduledAt,
    required bool repeatDaily,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final notificationId = notificationIdFor(id);
    final reminder = StudyReminder(
      id: id,
      targetId: targetId,
      targetTitle: targetTitle,
      targetType: targetType,
      scheduledAt: scheduledAt,
      repeatDaily: repeatDaily,
      notificationId: notificationId,
    );

    final all = await loadReminders()..add(reminder);
    await _saveAll(all);
    await _scheduleNotification(reminder);
    return reminder;
  }

  Future<void> deleteReminder(String id) async {
    final all = await loadReminders();
    StudyReminder? found;
    for (final r in all) {
      if (r.id == id) {
        found = r;
        break;
      }
    }
    if (found != null) {
      await NotificationService.instance.cancelReminder(found.notificationId);
    }
    all.removeWhere((r) => r.id == id);
    await _saveAll(all);
  }

  Future<void> updateReminderSchedule({
    required String id,
    required DateTime scheduledAt,
  }) async {
    final all = await loadReminders();
    final index = all.indexWhere((r) => r.id == id);
    if (index == -1) return;

    final existing = all[index];
    final updated = existing.copyWith(scheduledAt: scheduledAt);
    all[index] = updated;
    await _saveAll(all);
    await NotificationService.instance.cancelReminder(existing.notificationId);
    await _scheduleNotification(updated);
  }

  Future<void> rescheduleAll() async {
    final reminders = await loadReminders();
    for (final reminder in reminders) {
      if (!reminder.repeatDaily &&
          reminder.scheduledAt.isBefore(DateTime.now())) {
        continue;
      }
      try {
        await _scheduleNotification(reminder);
      } catch (_) {}
    }
  }

  Future<void> _scheduleNotification(StudyReminder reminder) async {
    final typeLabel =
        reminder.targetType == StudyReminderTargetType.note ? 'note' : 'file';
    await NotificationService.instance.scheduleStudyReminder(
      id: reminder.notificationId,
      title: 'Study reminder: ${reminder.targetTitle}',
      body: 'Time to review your $typeLabel "${reminder.targetTitle}".',
      scheduledTime: reminder.scheduledAt,
      repeatDaily: reminder.repeatDaily,
    );
  }
}
