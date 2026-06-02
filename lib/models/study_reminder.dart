enum StudyReminderTargetType { libraryFile, note }

class StudyReminder {
  final String id;
  final String targetId;
  final String targetTitle;
  final StudyReminderTargetType targetType;
  final DateTime scheduledAt;
  final bool repeatDaily;
  final int notificationId;

  const StudyReminder({
    required this.id,
    required this.targetId,
    required this.targetTitle,
    required this.targetType,
    required this.scheduledAt,
    required this.repeatDaily,
    required this.notificationId,
  });

  StudyReminder copyWith({
    String? id,
    String? targetId,
    String? targetTitle,
    StudyReminderTargetType? targetType,
    DateTime? scheduledAt,
    bool? repeatDaily,
    int? notificationId,
  }) {
    return StudyReminder(
      id: id ?? this.id,
      targetId: targetId ?? this.targetId,
      targetTitle: targetTitle ?? this.targetTitle,
      targetType: targetType ?? this.targetType,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      repeatDaily: repeatDaily ?? this.repeatDaily,
      notificationId: notificationId ?? this.notificationId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'targetId': targetId,
        'targetTitle': targetTitle,
        'targetType': targetType.name,
        'scheduledAt': scheduledAt.toIso8601String(),
        'repeatDaily': repeatDaily,
        'notificationId': notificationId,
      };

  factory StudyReminder.fromJson(Map<String, dynamic> json) {
    return StudyReminder(
      id: json['id'] as String,
      targetId: json['targetId'] as String,
      targetTitle: json['targetTitle'] as String? ?? 'Untitled',
      targetType: StudyReminderTargetType.values.firstWhere(
        (t) => t.name == json['targetType'],
        orElse: () => StudyReminderTargetType.libraryFile,
      ),
      scheduledAt: DateTime.parse(json['scheduledAt'] as String),
      repeatDaily: json['repeatDaily'] as bool? ?? false,
      notificationId: json['notificationId'] as int? ??
          (json['id'] as String).hashCode & 0x7FFFFFFF,
    );
  }
}
