class AppUser {
  final String id;
  final String fullName;
  final String username;
  final String role;
  final bool isActive;

  const AppUser({
    required this.id,
    required this.fullName,
    required this.username,
    required this.role,
    required this.isActive,
  });

  bool get isOwner => role == 'owner';

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id']?.toString() ?? '',
      fullName: map['full_name']?.toString().trim() ?? '',
      username: map['username']?.toString().trim() ?? '',
      role: map['role']?.toString().trim() ?? 'employee',
      isActive: map['is_active'] == true,
    );
  }
}
