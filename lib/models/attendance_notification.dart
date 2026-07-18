class AttendanceNotification {
  final int id;
  final String recipientId;
  final String? employeeId;
  final String? sessionId;
  final String eventType;
  final String title;
  final String message;
  final String placeName;
  final DateTime occurredAt;
  final DateTime? readAt;

  const AttendanceNotification({
    required this.id,
    required this.recipientId,
    required this.employeeId,
    required this.sessionId,
    required this.eventType,
    required this.title,
    required this.message,
    required this.placeName,
    required this.occurredAt,
    required this.readAt,
  });

  bool get isRead => readAt != null;
  bool get isCheckIn => eventType == 'check_in';
  bool get isCheckOut => eventType == 'check_out';

  factory AttendanceNotification.fromMap(Map<String, dynamic> map) {
    return AttendanceNotification(
      id: _asInt(map['id']),
      recipientId: map['recipient_id']?.toString() ?? '',
      employeeId: map['employee_id']?.toString(),
      sessionId: map['session_id']?.toString(),
      eventType: map['event_type']?.toString() ?? 'system',
      title: map['title']?.toString().trim() ?? 'Attendance Update',
      message: map['message']?.toString().trim() ?? '',
      placeName: map['place_name']?.toString().trim() ?? '',
      occurredAt: DateTime.parse(
        map['occurred_at']?.toString() ?? DateTime.now().toIso8601String(),
      ).toLocal(),
      readAt: map['read_at'] == null
          ? null
          : DateTime.parse(map['read_at'].toString()).toLocal(),
    );
  }

  static int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
