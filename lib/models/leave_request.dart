class LeaveRequest {
  final String id;
  final String employeeId;
  final String employeeName;
  final int leaveYear;
  final DateTime startDate;
  final DateTime endDate;
  final int workingDays;
  final String reason;
  final String status;
  final String reviewNote;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  const LeaveRequest({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.leaveYear,
    required this.startDate,
    required this.endDate,
    required this.workingDays,
    required this.reason,
    required this.status,
    required this.reviewNote,
    required this.reviewedAt,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory LeaveRequest.fromMap(Map<String, dynamic> map) {
    final profileValue = map['profiles'];
    Map<String, dynamic>? profile;
    if (profileValue is Map<String, dynamic>) {
      profile = profileValue;
    } else if (profileValue is List && profileValue.isNotEmpty) {
      final first = profileValue.first;
      if (first is Map<String, dynamic>) profile = first;
    }
    return LeaveRequest(
      id: map['id']?.toString() ?? '',
      employeeId: map['employee_id']?.toString() ?? '',
      employeeName: profile?['full_name']?.toString().trim().isNotEmpty == true
          ? profile!['full_name'].toString().trim()
          : 'Employee',
      leaveYear: _asInt(map['leave_year']),
      startDate: DateTime.parse(map['start_date'].toString()),
      endDate: DateTime.parse(map['end_date'].toString()),
      workingDays: _asInt(map['working_days']),
      reason: map['reason']?.toString().trim() ?? '',
      status: map['status']?.toString() ?? 'pending',
      reviewNote: map['review_note']?.toString().trim() ?? '',
      reviewedAt: map['reviewed_at'] == null
          ? null
          : DateTime.parse(map['reviewed_at'].toString()).toLocal(),
      createdAt: DateTime.parse(map['created_at'].toString()).toLocal(),
    );
  }

  static int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class LeaveBalance {
  final int year;
  final int annualAllowance;
  final int approvedDays;
  final int pendingDays;
  final int remainingDays;

  const LeaveBalance({
    required this.year,
    required this.annualAllowance,
    required this.approvedDays,
    required this.pendingDays,
    required this.remainingDays,
  });

  factory LeaveBalance.fromMap(Map<String, dynamic> map) {
    int number(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }
    return LeaveBalance(
      year: number(map['leave_year']),
      annualAllowance: number(map['annual_allowance']),
      approvedDays: number(map['approved_days']),
      pendingDays: number(map['pending_days']),
      remainingDays: number(map['remaining_days']),
    );
  }
}
