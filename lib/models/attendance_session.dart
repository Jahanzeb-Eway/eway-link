class AttendanceSession {
  final String id;
  final String employeeId;
  final String employeeName;
  final DateTime workDate;
  final DateTime checkedInAt;
  final DateTime? checkedOutAt;
  final double checkInLatitude;
  final double checkInLongitude;
  final double checkInAccuracy;
  final String checkInAddress;
  final double? checkOutLatitude;
  final double? checkOutLongitude;
  final double? checkOutAccuracy;
  final String checkOutAddress;
  final String status;
  final int locationPointCount;

  const AttendanceSession({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.workDate,
    required this.checkedInAt,
    required this.checkedOutAt,
    required this.checkInLatitude,
    required this.checkInLongitude,
    required this.checkInAccuracy,
    required this.checkInAddress,
    required this.checkOutLatitude,
    required this.checkOutLongitude,
    required this.checkOutAccuracy,
    required this.checkOutAddress,
    required this.status,
    this.locationPointCount = 0,
  });

  bool get isOpen => checkedOutAt == null && status == 'checked_in';

  Duration get workedDuration =>
      (checkedOutAt ?? DateTime.now()).difference(checkedInAt);

  AttendanceSession copyWith({int? locationPointCount}) {
    return AttendanceSession(
      id: id,
      employeeId: employeeId,
      employeeName: employeeName,
      workDate: workDate,
      checkedInAt: checkedInAt,
      checkedOutAt: checkedOutAt,
      checkInLatitude: checkInLatitude,
      checkInLongitude: checkInLongitude,
      checkInAccuracy: checkInAccuracy,
      checkInAddress: checkInAddress,
      checkOutLatitude: checkOutLatitude,
      checkOutLongitude: checkOutLongitude,
      checkOutAccuracy: checkOutAccuracy,
      checkOutAddress: checkOutAddress,
      status: status,
      locationPointCount: locationPointCount ?? this.locationPointCount,
    );
  }

  factory AttendanceSession.fromMap(Map<String, dynamic> map) {
    final profileValue = map['profiles'];
    Map<String, dynamic>? profile;
    if (profileValue is Map<String, dynamic>) {
      profile = profileValue;
    } else if (profileValue is List && profileValue.isNotEmpty) {
      final first = profileValue.first;
      if (first is Map<String, dynamic>) profile = first;
    }

    final checkedInAt = DateTime.parse(
      map['checked_in_at'].toString(),
    ).toLocal();
    final rawWorkDate = map['work_date']?.toString();

    return AttendanceSession(
      id: map['id'].toString(),
      employeeId: map['employee_id'].toString(),
      employeeName: profile?['full_name']?.toString().trim() ?? '',
      workDate: rawWorkDate == null || rawWorkDate.isEmpty
          ? DateTime(checkedInAt.year, checkedInAt.month, checkedInAt.day)
          : DateTime.parse(rawWorkDate),
      checkedInAt: checkedInAt,
      checkedOutAt: map['checked_out_at'] == null
          ? null
          : DateTime.parse(map['checked_out_at'].toString()).toLocal(),
      checkInLatitude: _asDouble(map['check_in_latitude']),
      checkInLongitude: _asDouble(map['check_in_longitude']),
      checkInAccuracy: _asDouble(map['check_in_accuracy']),
      checkInAddress: _address(map['check_in_address']),
      checkOutLatitude: _asNullableDouble(map['check_out_latitude']),
      checkOutLongitude: _asNullableDouble(map['check_out_longitude']),
      checkOutAccuracy: _asNullableDouble(map['check_out_accuracy']),
      checkOutAddress: _address(map['check_out_address']),
      status: map['status']?.toString() ?? 'checked_in',
      locationPointCount: _asInt(map['location_point_count']),
    );
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _asNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _address(dynamic value) {
    final address = value?.toString().trim() ?? '';
    return address.isEmpty ? 'Location name not recorded' : address;
  }
}

class AttendanceDailyEmployee {
  final String employeeId;
  final String employeeName;
  final String role;
  final AttendanceSession? session;
  final bool isOnLeave;
  final bool isWeekend;

  const AttendanceDailyEmployee({
    required this.employeeId,
    required this.employeeName,
    required this.role,
    required this.session,
    this.isOnLeave = false,
    this.isWeekend = false,
  });

  bool get isPresent => session != null;
  bool get isTracking => session?.isOpen == true;
  bool get isCompleted => session != null && !isTracking;
}
