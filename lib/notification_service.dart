import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Result of checking notification + exact-alarm permissions (Android).
class ReminderPermissionStatus {
  const ReminderPermissionStatus({
    required this.notificationsGranted,
    required this.exactAlarmsGranted,
  });

  final bool notificationsGranted;
  final bool exactAlarmsGranted;

  bool get canScheduleReliably =>
      notificationsGranted && exactAlarmsGranted;

  bool get canShowNotifications => notificationsGranted;
}

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _remindersChannel =
      AndroidNotificationChannel(
    'reminders',
    'Reminders',
    description: 'Study and reading reminders for your files and notes',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  static const AndroidNotificationChannel _dailyChannel =
      AndroidNotificationChannel(
    'daily_reminders',
    'Daily Reminders',
    description: 'Reminders to stay consistent with your reading goals',
    importance: Importance.high,
  );

  Future<void> init() async {
    tz.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (e) {
      debugPrint('NotificationService: timezone setup failed: $e');
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
    );

    await _createAndroidChannels();
  }

  Future<void> _createAndroidChannels() async {
    final android = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_remindersChannel);
    await android?.createNotificationChannel(_dailyChannel);
  }

  Future<ReminderPermissionStatus> checkReminderPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final notificationsOk =
          await android?.areNotificationsEnabled() ?? true;
      final exactOk =
          await android?.canScheduleExactNotifications() ?? true;
      return ReminderPermissionStatus(
        notificationsGranted: notificationsOk,
        exactAlarmsGranted: exactOk,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _notificationsPlugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final settings = await ios?.checkPermissions();
      final granted = settings?.isEnabled ?? false;
      return ReminderPermissionStatus(
        notificationsGranted: granted,
        exactAlarmsGranted: true,
      );
    }
    return const ReminderPermissionStatus(
      notificationsGranted: true,
      exactAlarmsGranted: true,
    );
  }

  /// Requests OS permissions when the user is setting a reminder (with UI context).
  Future<ReminderPermissionStatus> requestReminderPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      var notificationStatus = await Permission.notification.status;
      if (!notificationStatus.isGranted) {
        notificationStatus = await Permission.notification.request();
      }

      final android = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (!(await android?.areNotificationsEnabled() ?? false)) {
        await android?.requestNotificationsPermission();
      }

      var exactStatus = await Permission.scheduleExactAlarm.status;
      if (!exactStatus.isGranted) {
        exactStatus = await Permission.scheduleExactAlarm.request();
        await android?.requestExactAlarmsPermission();
      }

      return checkReminderPermissions();
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _notificationsPlugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
      return checkReminderPermissions();
    }

    return const ReminderPermissionStatus(
      notificationsGranted: true,
      exactAlarmsGranted: true,
    );
  }

  @Deprecated('Use requestReminderPermissions when user adds a reminder')
  Future<void> requestPermissions() => requestReminderPermissions().then((_) {});

  Future<bool> canScheduleReminders() async {
    final status = await checkReminderPermissions();
    return status.canShowNotifications;
  }

  Future<void> cancelReminder(int id) async {
    await _notificationsPlugin.cancel(id: id);
  }

  Future<void> scheduleDailyReminder(int hour, int minute) async {
    final status = await checkReminderPermissions();
    if (!status.canShowNotifications) return;

    await _notificationsPlugin.zonedSchedule(
      id: 0,
      title: 'Ready to Study?',
      body:
          'You haven\'t met your reading goal yet today. Keep your streak alive!',
      scheduledDate: _nextInstanceOfTime(hour, minute),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _dailyChannel.id,
          _dailyChannel.name,
          channelDescription: _dailyChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: _scheduleMode(status),
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> showInstantNotification(String title, String body) async {
    const android = AndroidNotificationDetails(
      'instant_alerts',
      'Instant Alerts',
      importance: Importance.max,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();
    const details = NotificationDetails(android: android, iOS: ios);

    await _notificationsPlugin.show(
      id: DateTime.now().millisecond,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) {
    return scheduleStudyReminder(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      repeatDaily: false,
    );
  }

  Future<void> scheduleStudyReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    bool repeatDaily = false,
  }) async {
    final status = await checkReminderPermissions();
    if (!status.canShowNotifications) {
      debugPrint('NotificationService: notifications disabled, skip $id');
      return;
    }

    final tz.TZDateTime when = repeatDaily
        ? _nextInstanceOfTime(scheduledTime.hour, scheduledTime.minute)
        : tz.TZDateTime.from(scheduledTime, tz.local);

    if (!repeatDaily && when.isBefore(tz.TZDateTime.now(tz.local))) {
      debugPrint('NotificationService: skipped past reminder $id');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription:
          'Study and reading reminders for your files and notes',
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      ticker: 'Vox study reminder',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    try {
      await _notificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: const NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        androidScheduleMode: _scheduleMode(status),
        matchDateTimeComponents:
            repeatDaily ? DateTimeComponents.time : null,
      );
      debugPrint(
        'NotificationService: scheduled $id at $when (exact=${status.exactAlarmsGranted})',
      );
    } catch (e, st) {
      debugPrint('NotificationService: schedule failed for $id: $e\n$st');
      rethrow;
    }
  }

  AndroidScheduleMode _scheduleMode(ReminderPermissionStatus status) {
    if (status.exactAlarmsGranted) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}
