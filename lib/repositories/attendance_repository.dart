import 'package:geolocator/geolocator.dart';

import '../models/attendance_session.dart';
import '../services/supabase_service.dart';

class AttendanceRepository {
  AttendanceRepository._();

  static final AttendanceRepository instance = AttendanceRepository._();

  final _db = SupabaseService.client;

  static const _sessionColumns =
      'id, employee_id, work_date, checked_in_at, checked_out_at, '
      'check_in_latitude, check_in_longitude, check_in_accuracy, '
      'check_in_address, check_out_latitude, check_out_longitude, '
      'check_out_accuracy, check_out_address, status';

  static const _ownerSessionColumns =
      '$_sessionColumns, '
      'profiles!attendance_sessions_employee_id_fkey(full_name, role)';

  Future<AttendanceSession?> getOpenSession() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;

    final data = await _db
        .from('attendance_sessions')
        .select(_sessionColumns)
        .eq('employee_id', user.id)
        .isFilter('checked_out_at', null)
        .maybeSingle();

    return data == null ? null : AttendanceSession.fromMap(data);
  }

  Future<bool> hasOperationalAccessToday() async {
    final user = _db.auth.currentUser;
    if (user == null) return false;

    final pakistanNow = DateTime.now().toUtc().add(const Duration(hours: 5));
    final todayKey = _dateKey(pakistanNow);
    final rows = await _db
        .from('attendance_sessions')
        .select('work_date, checked_in_at, checked_out_at, status')
        .eq('employee_id', user.id)
        .order('checked_in_at', ascending: false)
        .limit(10);

    for (final row in List<Map<String, dynamic>>.from(rows)) {
      if (row['work_date']?.toString() == todayKey) return true;

      final checkedOutAt = DateTime.tryParse(
        row['checked_out_at']?.toString() ?? '',
      );
      final isOpen = checkedOutAt == null &&
          row['status']?.toString().toLowerCase() == 'checked_in';
      if (isOpen) return true;

      final checkedInAt = DateTime.tryParse(
        row['checked_in_at']?.toString() ?? '',
      );
      if (checkedInAt != null &&
          _dateKey(checkedInAt.toUtc().add(const Duration(hours: 5))) ==
              todayKey) {
        return true;
      }
      if (checkedOutAt != null &&
          _dateKey(checkedOutAt.toUtc().add(const Duration(hours: 5))) ==
              todayKey) {
        return true;
      }
    }
    return false;
  }

  Future<AttendanceSession> checkIn(
    Position position, {
    required String address,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw StateError('Employee login is required.');
    if (await getOpenSession() != null) {
      throw StateError('You are already checked in.');
    }

    final data = await _db
        .from('attendance_sessions')
        .insert({
          'employee_id': user.id,
          'check_in_latitude': position.latitude,
          'check_in_longitude': position.longitude,
          'check_in_accuracy': position.accuracy,
          'check_in_address': address,
          'status': 'checked_in',
        })
        .select(_sessionColumns)
        .single();

    final session = AttendanceSession.fromMap(data);
    await addPoint(session.id, user.id, position, placeName: address);
    return session;
  }

  Future<void> checkOut(
    AttendanceSession session,
    Position position, {
    required String address,
  }) async {
    await addPoint(
      session.id,
      session.employeeId,
      position,
      placeName: address,
    );
    await _db
        .from('attendance_sessions')
        .update({
          'checked_out_at': DateTime.now().toUtc().toIso8601String(),
          'check_out_latitude': position.latitude,
          'check_out_longitude': position.longitude,
          'check_out_accuracy': position.accuracy,
          'check_out_address': address,
          'status': 'checked_out',
        })
        .eq('id', session.id)
        .eq('employee_id', session.employeeId);
  }

  Future<void> addPoint(
    String sessionId,
    String employeeId,
    Position position, {
    String? placeName,
  }) async {
    await _db.from('attendance_location_points').insert({
      'session_id': sessionId,
      'employee_id': employeeId,
      'recorded_at': position.timestamp.toUtc().toIso8601String(),
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'altitude': position.altitude,
      'speed': position.speed,
      'heading': position.heading,
      'is_mocked': position.isMocked,
      'place_name': placeName,
    });
  }

  Future<List<AttendanceSession>> history({int limit = 31}) async {
    final user = _db.auth.currentUser;
    if (user == null) return [];

    final rows = await _db
        .from('attendance_sessions')
        .select(_sessionColumns)
        .eq('employee_id', user.id)
        .order('checked_in_at', ascending: false)
        .limit(limit);

    return List<Map<String, dynamic>>.from(
      rows,
    ).map(AttendanceSession.fromMap).toList();
  }

  Future<List<AttendanceDailyEmployee>> ownerDailyOverview(
    DateTime date,
  ) async {
    final dateKey = _dateKey(date);
    final isWeekend = date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;
    final results = await Future.wait([
      _db
          .from('profiles')
          .select('id, full_name, role')
          .eq('is_active', true)
          .order('full_name'),
      _db
          .from('attendance_sessions')
          .select(_ownerSessionColumns)
          .eq('work_date', dateKey)
          .order('checked_in_at'),
      _db
          .from('leave_requests')
          .select('employee_id')
          .eq('status', 'approved')
          .lte('start_date', dateKey)
          .gte('end_date', dateKey),
    ]);

    final profileRows = List<Map<String, dynamic>>.from(results[0] as List);
    final sessionRows = List<Map<String, dynamic>>.from(results[1] as List);
    final leaveRows = List<Map<String, dynamic>>.from(results[2] as List);
    final employeesOnLeave = leaveRows
        .map((row) => row['employee_id']?.toString())
        .whereType<String>()
        .toSet();
    final sessions = await _withPointCounts(
      sessionRows.map(AttendanceSession.fromMap).toList(),
    );
    final sessionsByEmployee = {
      for (final session in sessions) session.employeeId: session,
    };

    return profileRows.map((profile) {
      final id = profile['id'].toString();
      return AttendanceDailyEmployee(
        employeeId: id,
        employeeName: profile['full_name']?.toString().trim().isNotEmpty == true
            ? profile['full_name'].toString().trim()
            : 'Unnamed Employee',
        role: profile['role']?.toString() ?? 'employee',
        session: sessionsByEmployee[id],
        isOnLeave: !isWeekend && employeesOnLeave.contains(id),
        isWeekend: isWeekend,
      );
    }).toList();
  }

  Future<List<AttendanceSession>> ownerHistory({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _db
        .from('attendance_sessions')
        .select(_ownerSessionColumns)
        .gte('work_date', _dateKey(from))
        .lte('work_date', _dateKey(to))
        .order('checked_in_at', ascending: false);

    final sessions = List<Map<String, dynamic>>.from(
      rows,
    ).map(AttendanceSession.fromMap).toList();
    return _withPointCounts(sessions);
  }

  Future<List<AttendanceSession>> _withPointCounts(
    List<AttendanceSession> sessions,
  ) async {
    if (sessions.isEmpty) return sessions;

    final ids = sessions.map((session) => session.id).toList();
    final rows = await _db
        .from('attendance_location_points')
        .select('session_id')
        .inFilter('session_id', ids);

    final counts = <String, int>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final sessionId = row['session_id']?.toString();
      if (sessionId != null) {
        counts[sessionId] = (counts[sessionId] ?? 0) + 1;
      }
    }

    return sessions
        .map(
          (session) => session.copyWith(
            locationPointCount: counts[session.id] ?? 0,
          ),
        )
        .toList();
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
