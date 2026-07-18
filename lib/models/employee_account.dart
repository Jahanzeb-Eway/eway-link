class EmployeeAccount {
  final String id;
  final String fullName;
  final String username;
  final String role;
  final bool isActive;

  const EmployeeAccount({
    required this.id,
    required this.fullName,
    required this.username,
    required this.role,
    required this.isActive,
  });

  String get roleLabel {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'coordinator':
        return 'Coordinator';
      default:
        return 'Employee';
    }
  }

  factory EmployeeAccount.fromMap(Map<String, dynamic> map) {
    return EmployeeAccount(
      id: map['id']?.toString() ?? '',
      fullName: map['full_name']?.toString().trim() ?? '',
      username: map['username']?.toString().trim() ?? '',
      role: map['role']?.toString().trim() ?? 'employee',
      isActive: map['is_active'] == true,
    );
  }
}
