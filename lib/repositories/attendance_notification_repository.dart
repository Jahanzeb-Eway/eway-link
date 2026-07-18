import '../models/attendance_notification.dart';
import '../services/supabase_service.dart';

class AttendanceNotificationRepository {
  AttendanceNotificationRepository._();

  static final AttendanceNotificationRepository instance =
      AttendanceNotificationRepository._();

  final _db = SupabaseService.client;

  Stream<List<AttendanceNotification>> watch() {
    final user = _db.auth.currentUser;
    if (user == null) return Stream.value(const []);

    return _db
        .from('attendance_notifications')
        .stream(primaryKey: ['id'])
        .eq('recipient_id', user.id)
        .order('occurred_at', ascending: false)
        .limit(100)
        .map(
          (rows) => rows
              .map(AttendanceNotification.fromMap)
              .toList(growable: false),
        );
  }

  Future<void> markRead(int notificationId) async {
    final user = _db.auth.currentUser;
    if (user == null) return;

    await _db
        .from('attendance_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', notificationId)
        .eq('recipient_id', user.id)
        .isFilter('read_at', null);
  }

  Future<void> markAllRead() async {
    final user = _db.auth.currentUser;
    if (user == null) return;

    await _db
        .from('attendance_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('recipient_id', user.id)
        .isFilter('read_at', null);
  }
}
