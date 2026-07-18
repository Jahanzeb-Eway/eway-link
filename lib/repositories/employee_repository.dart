import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee_account.dart';
import '../services/supabase_service.dart';

class EmployeeRepository {
  EmployeeRepository({SupabaseClient? client})
      : _db = client ?? SupabaseService.client;

  final SupabaseClient _db;

  Future<List<EmployeeAccount>> fetchEmployees() async {
    final rows = await _db
        .from('profiles')
        .select('id, full_name, username, role, is_active')
        .order('full_name');
    return List<Map<String, dynamic>>.from(rows)
        .map(EmployeeAccount.fromMap)
        .toList();
  }

  Future<void> createEmployee({
    required String fullName,
    required String username,
    required String role,
    required String temporaryPassword,
  }) async {
    await _invoke({
      'action': 'create',
      'full_name': fullName.trim(),
      'username': username.trim().toLowerCase(),
      'role': role,
      'password': temporaryPassword,
    });
  }

  Future<void> setActive({
    required String employeeId,
    required bool isActive,
  }) async {
    await _invoke({
      'action': 'set_active',
      'employee_id': employeeId,
      'is_active': isActive,
    });
  }

  Future<void> resetPassword({
    required String employeeId,
    required String password,
  }) async {
    await _invoke({
      'action': 'reset_password',
      'employee_id': employeeId,
      'password': password,
    });
  }

  Future<void> _invoke(Map<String, dynamic> body) async {
    final response = await _db.functions.invoke(
      'manage-employee',
      body: body,
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map
          ? data['message']?.toString()
          : data?.toString();
      throw Exception(
        message?.trim().isNotEmpty == true
            ? message
            : 'The employee account operation failed.',
      );
    }
  }
}
