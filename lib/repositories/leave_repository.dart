import '../models/leave_request.dart';
import '../services/supabase_service.dart';

class LeaveRepository {
  LeaveRepository._();

  static final LeaveRepository instance = LeaveRepository._();
  final _db = SupabaseService.client;

  static const _baseColumns =
      'id, employee_id, leave_year, start_date, end_date, working_days, '
      'reason, status, reviewed_at, review_note, created_at';

  static const _ownerColumns =
      '$_baseColumns, '
      'profiles!leave_requests_employee_id_fkey(full_name)';

  Future<LeaveBalance> myBalance({int? year}) async {
    final selectedYear = year ?? DateTime.now().year;
    try {
      final response = await _db.rpc(
        'get_my_leave_balance',
        params: {'p_year': selectedYear},
      );
      final rows = response is List ? response : [response];
      if (rows.isNotEmpty && rows.first is Map) {
        return LeaveBalance.fromMap(
          Map<String, dynamic>.from(rows.first as Map),
        );
      }
    } catch (_) {
      final user = _db.auth.currentUser;
      if (user == null) throw StateError('Employee login is required.');
      final rows = await _db
          .from('leave_requests')
          .select('working_days, status')
          .eq('employee_id', user.id)
          .eq('leave_year', selectedYear);
      var approved = 0;
      var pending = 0;
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final value = row['working_days'];
        final days = value is num
            ? value.toInt()
            : int.tryParse(value?.toString() ?? '') ?? 0;
        if (row['status'] == 'approved') approved += days;
        if (row['status'] == 'pending') pending += days;
      }
      return LeaveBalance(
        year: selectedYear,
        annualAllowance: 21,
        approvedDays: approved,
        pendingDays: pending,
        remainingDays: (21 - approved).clamp(0, 21).toInt(),
      );
    }
    throw StateError('The leave balance could not be loaded.');
  }

  Future<List<LeaveRequest>> myRequests() async {
    final user = _db.auth.currentUser;
    if (user == null) return const [];
    final rows = await _db
        .from('leave_requests')
        .select(_baseColumns)
        .eq('employee_id', user.id)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows)
        .map(LeaveRequest.fromMap)
        .toList(growable: false);
  }

  Future<List<LeaveRequest>> ownerRequests() async {
    final rows = await _db
        .from('leave_requests')
        .select(_ownerColumns)
        .order('created_at', ascending: false)
        .limit(200);
    return List<Map<String, dynamic>>.from(rows)
        .map(LeaveRequest.fromMap)
        .toList(growable: false);
  }

  Future<void> apply({
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    await _db.rpc(
      'apply_for_leave',
      params: {
        'p_start_date': _dateKey(startDate),
        'p_end_date': _dateKey(endDate),
        'p_reason': reason.trim(),
      },
    );
  }

  Future<void> review({
    required String requestId,
    required bool approve,
    String reviewNote = '',
  }) async {
    await _db.rpc(
      'review_leave_request',
      params: {
        'p_request_id': requestId,
        'p_approve': approve,
        'p_review_note': reviewNote.trim(),
      },
    );
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
