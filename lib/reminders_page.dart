import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'language_provider.dart';
import 'models/study_reminder.dart';
import 'services/auth_session.dart';
import 'services/reminders_service.dart';
import 'notification_service.dart';
import 'temp_library_provider.dart';
import 'temp_notes_provider.dart';
import 'theme_provider.dart';

class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  List<StudyReminder> _reminders = [];
  bool _loading = true;
  String? _uid;
  ReminderPermissionStatus? _permissionStatus;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final session = await AuthSession.resolveForApp();
    _uid = session.uid;
    await _reload();
    await _refreshPermissionStatus();
    if (!mounted) return;
    final status = _permissionStatus;
    if (status != null && !status.canShowNotifications) {
      await _promptForReminderPermissions();
    }
  }

  Future<void> _refreshPermissionStatus() async {
    final status =
        await NotificationService.instance.checkReminderPermissions();
    if (!mounted) return;
    setState(() => _permissionStatus = status);
  }

  Future<bool> _promptForReminderPermissions() async {
    final lang = context.read<LanguageProvider>();

    final proceedNotif = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(lang.t('notification_permission_title')),
        content: Text(lang.t('notification_permission_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lang.t('enable_notifications')),
          ),
        ],
      ),
    );
    if (proceedNotif != true || !mounted) return false;

    var status =
        await NotificationService.instance.requestReminderPermissions();
    await _refreshPermissionStatus();

    if (!status.notificationsGranted && mounted) {
      final permanentlyDenied =
          await Permission.notification.isPermanentlyDenied;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.t('notification_permission_denied')),
          behavior: SnackBarBehavior.floating,
          action: permanentlyDenied
              ? SnackBarAction(
                  label: lang.t('settings'),
                  onPressed: openAppSettings,
                )
              : null,
        ),
      );
      return false;
    }

    if (!status.exactAlarmsGranted && mounted) {
      final openExact = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(lang.t('exact_alarm_permission_title')),
          content: Text(lang.t('exact_alarm_permission_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(lang.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(lang.t('enable_notifications')),
            ),
          ],
        ),
      );
      if (openExact == true) {
        await Permission.scheduleExactAlarm.request();
        await NotificationService.instance.requestReminderPermissions();
        status =
            await NotificationService.instance.checkReminderPermissions();
        await _refreshPermissionStatus();
      }
    }

    return status.canShowNotifications;
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final items = await RemindersService.instance.loadReminders();
    if (!mounted) return;
    setState(() {
      _reminders = items;
      _loading = false;
    });
  }

  Future<void> _deleteReminder(StudyReminder reminder) async {
    final lang = context.read<LanguageProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.t('delete_reminder_title')),
        content: Text(lang.t('delete_reminder_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lang.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await RemindersService.instance.deleteReminder(reminder.id);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(lang.t('reminder_deleted'))),
    );
  }

  Future<void> _editReminderTime(StudyReminder reminder) async {
    final lang = context.read<LanguageProvider>();

    final permissionsOk = await _promptForReminderPermissions();
    if (!permissionsOk || !mounted) return;

    DateTime scheduled = reminder.scheduledAt;

    if (reminder.repeatDaily) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(reminder.scheduledAt),
        helpText: lang.t('edit_reminder_time'),
      );
      if (time == null || !mounted) return;
      scheduled = DateTime(
        reminder.scheduledAt.year,
        reminder.scheduledAt.month,
        reminder.scheduledAt.day,
        time.hour,
        time.minute,
      );
    } else {
      final date = await showDatePicker(
        context: context,
        initialDate: reminder.scheduledAt,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        helpText: lang.t('edit_reminder_time'),
      );
      if (date == null || !mounted) return;

      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(reminder.scheduledAt),
        helpText: lang.t('edit_reminder_time'),
      );
      if (time == null || !mounted) return;

      scheduled = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (scheduled.isBefore(DateTime.now())) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
    }

    await RemindersService.instance.updateReminderSchedule(
      id: reminder.id,
      scheduledAt: scheduled,
    );

    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(lang.t('reminder_updated'))),
    );
  }

  Future<void> _showAddReminderSheet() async {
    final lang = context.read<LanguageProvider>();

    final permissionsOk = await _promptForReminderPermissions();
    if (!permissionsOk || !mounted) return;

    final library = context.read<TempLibraryProvider>().items;
    final tempNotes = context.read<TempNotesProvider>().notes;

    final picked = await showModalBottomSheet<_PickTarget>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PickTargetSheet(
        uid: _uid,
        tempLibrary: library,
        tempNotes: tempNotes,
      ),
    );
    if (picked == null || !mounted) return;

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;

    var scheduled = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (scheduled.isBefore(DateTime.now())) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final repeatDaily = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.t('repeat_reminder_title')),
        content: Text(lang.t('repeat_reminder_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.t('reminder_once')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lang.t('reminder_daily')),
          ),
        ],
      ),
    );
    if (repeatDaily == null || !mounted) return;

    await RemindersService.instance.addReminder(
      targetId: picked.id,
      targetTitle: picked.title,
      targetType: picked.type,
      scheduledAt: scheduled,
      repeatDaily: repeatDaily,
    );

    await _reload();
    await _refreshPermissionStatus();
    if (!mounted) return;
    final label = TimeOfDay.fromDateTime(scheduled).format(context);
    final status = _permissionStatus ??
        await NotificationService.instance.checkReminderPermissions();
    final base = lang.tNamed('reminder_set_for', {
      'title': picked.title,
      'time': label,
    });
    var message = base;
    if (!status.canShowNotifications) {
      message = '$base\n${lang.t('notification_permission_denied')}';
    } else if (!status.exactAlarmsGranted) {
      message = '$base\n${lang.t('exact_alarm_permission_denied')}';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  String _formatWhen(StudyReminder reminder, LanguageProvider lang) {
    final time = TimeOfDay.fromDateTime(reminder.scheduledAt).format(context);
    if (reminder.repeatDaily) {
      return lang.tNamed('reminder_daily_at', {'time': time});
    }
    final date = reminder.scheduledAt;
    final dateLabel = '${date.month}/${date.day}/${date.year}';
    return lang.tNamed('reminder_once_at', {'date': dateLabel, 'time': time});
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();

    return Scaffold(
      backgroundColor: VoxColors.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: VoxColors.onBg(context)),
        title: Text(
          lang.t('menu_reminders'),
          style: TextStyle(
            color: VoxColors.onBg(context),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddReminderSheet,
        backgroundColor: VoxColors.primary(context),
        foregroundColor: VoxColors.onPrimary(context),
        icon: const Icon(Icons.add_alarm),
        label: Text(lang.t('add_reminder')),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: VoxColors.primary(context)),
            )
          : Column(
              children: [
                if (_permissionStatus != null &&
                    !_permissionStatus!.canShowNotifications)
                  _PermissionBanner(
                    onEnable: _promptForReminderPermissions,
                  ),
                Expanded(
                  child: _reminders.isEmpty
                      ? _EmptyReminders(onAdd: _showAddReminderSheet)
                      : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: _reminders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final reminder = _reminders[index];
                    final isNote =
                        reminder.targetType == StudyReminderTargetType.note;
                    return Container(
                      decoration: BoxDecoration(
                        color: VoxColors.surface(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: VoxColors.border(context)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        leading: CircleAvatar(
                          backgroundColor: VoxColors.primary(context)
                              .withValues(alpha: 0.12),
                          child: Icon(
                            isNote
                                ? Icons.mic_none_rounded
                                : Icons.description_outlined,
                            color: VoxColors.primary(context),
                          ),
                        ),
                        title: Text(
                          reminder.targetTitle,
                          style: TextStyle(
                            color: VoxColors.onSurface(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              _formatWhen(reminder, lang),
                              style: TextStyle(
                                color: VoxColors.textSecondary(context),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isNote
                                  ? lang.t('reminder_type_note')
                                  : lang.t('reminder_type_file'),
                              style: TextStyle(
                                color: VoxColors.textHint(context),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.schedule_outlined,
                                color: VoxColors.primary(context),
                              ),
                              tooltip: lang.t('edit_reminder_time'),
                              onPressed: () => _editReminderTime(reminder),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: VoxColors.danger,
                              ),
                              onPressed: () => _deleteReminder(reminder),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                ),
              ],
            ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.onEnable});

  final Future<bool> Function() onEnable;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    return Material(
      color: VoxColors.primary(context).withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Icon(Icons.notifications_off_outlined,
                color: VoxColors.primary(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                lang.t('reminders_need_permissions'),
                style: TextStyle(
                  color: VoxColors.onBg(context),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            TextButton(
              onPressed: () => onEnable(),
              child: Text(lang.t('enable_notifications')),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickTarget {
  final String id;
  final String title;
  final StudyReminderTargetType type;

  const _PickTarget({
    required this.id,
    required this.title,
    required this.type,
  });
}

class _PickTargetSheet extends StatefulWidget {
  final String? uid;
  final List<dynamic> tempLibrary;
  final List<dynamic> tempNotes;

  const _PickTargetSheet({
    required this.uid,
    required this.tempLibrary,
    required this.tempNotes,
  });

  @override
  State<_PickTargetSheet> createState() => _PickTargetSheetState();
}

class _PickTargetSheetState extends State<_PickTargetSheet> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final height = MediaQuery.of(context).size.height * 0.72;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: VoxColors.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: VoxColors.border(context),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              lang.t('pick_reminder_target'),
              style: TextStyle(
                color: VoxColors.onSurface(context),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _tabChip(context, lang.t('reminder_tab_files'), 0),
                const SizedBox(width: 8),
                _tabChip(context, lang.t('reminder_tab_notes'), 1),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _tab == 0 ? _buildFilesList(lang) : _buildNotesList(lang),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(BuildContext context, String label, int index) {
    final selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? VoxColors.primary(context)
                : VoxColors.cardFill(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? VoxColors.primary(context)
                  : VoxColors.border(context),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected
                  ? VoxColors.onPrimary(context)
                  : VoxColors.onSurface(context),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilesList(LanguageProvider lang) {
    final tempItems = widget.tempLibrary.map((item) {
      return _PickTarget(
        id: item.id as String,
        title: item.fileName as String,
        type: StudyReminderTargetType.libraryFile,
      );
    }).toList();

    if (widget.uid == null) {
      return _targetList(tempItems, lang);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('library')
          .where('userId', isEqualTo: widget.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final cloudItems = <_PickTarget>[];
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final name = (data['fileName'] as String?)?.trim();
            if (name == null || name.isEmpty) continue;
            cloudItems.add(
              _PickTarget(
                id: doc.id,
                title: name,
                type: StudyReminderTargetType.libraryFile,
              ),
            );
          }
        }

        final merged = <String, _PickTarget>{};
        for (final item in [...cloudItems, ...tempItems]) {
          merged['${item.type.name}:${item.id}'] = item;
        }
        return _targetList(merged.values.toList(), lang);
      },
    );
  }

  Widget _buildNotesList(LanguageProvider lang) {
    final tempItems = widget.tempNotes.map((note) {
      return _PickTarget(
        id: note.id as String,
        title: note.title as String,
        type: StudyReminderTargetType.note,
      );
    }).toList();

    final uid = widget.uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _targetList(tempItems, lang);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notes')
          .where('userId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        final cloudItems = <_PickTarget>[];
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final title = (data['title'] as String?)?.trim();
            if (title == null || title.isEmpty) continue;
            cloudItems.add(
              _PickTarget(
                id: doc.id,
                title: title,
                type: StudyReminderTargetType.note,
              ),
            );
          }
        }

        final merged = <String, _PickTarget>{};
        for (final item in [...cloudItems, ...tempItems]) {
          merged['${item.type.name}:${item.id}'] = item;
        }
        return _targetList(merged.values.toList(), lang);
      },
    );
  }

  Widget _targetList(List<_PickTarget> items, LanguageProvider lang) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            lang.t('no_reminder_targets'),
            textAlign: TextAlign.center,
            style: TextStyle(color: VoxColors.textHint(context)),
          ),
        ),
      );
    }

    items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(color: VoxColors.border(context)),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          title: Text(
            item.title,
            style: TextStyle(
              color: VoxColors.onSurface(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: VoxColors.textHint(context)),
          onTap: () => Navigator.pop(context, item),
        );
      },
    );
  }
}

class _EmptyReminders extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyReminders({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 64,
              color: VoxColors.textHint(context),
            ),
            const SizedBox(height: 16),
            Text(
              lang.t('reminders_empty_title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: VoxColors.onBg(context),
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              lang.t('reminders_empty_body'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: VoxColors.textSecondary(context),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_alarm),
              label: Text(lang.t('add_reminder')),
              style: ElevatedButton.styleFrom(
                backgroundColor: VoxColors.primary(context),
                foregroundColor: VoxColors.onPrimary(context),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
