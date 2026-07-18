import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import 'push_notification_service.dart';
import 'supabase_service.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final SupabaseClient _db = SupabaseService.client;
  AppUser? _cachedProfile;

  Session? get currentSession => _db.auth.currentSession;
  User? get currentAuthUser => _db.auth.currentUser;
  AppUser? get cachedProfile => _cachedProfile;
  Stream<AuthState> get authStateChanges => _db.auth.onAuthStateChange;

  Future<AppUser> signIn({
    required String username,
    required String password,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9._-]{3,32}$').hasMatch(normalizedUsername)) {
      throw const AuthException('Enter a valid username.');
    }
    final resolvedEmail = await _db.rpc<String?>(
      'resolve_login_email',
      params: {'p_username': normalizedUsername},
    );
    if (resolvedEmail == null || resolvedEmail.trim().isEmpty) {
      throw const AuthException('Login failed. Please check your credentials.');
    }
    final response = await _db.auth.signInWithPassword(
      email: resolvedEmail.trim(),
      password: password,
    );
    if (response.user == null) {
      throw const AuthException('Login failed. Please check your credentials.');
    }
    final profile = await loadCurrentProfile(forceRefresh: true);
    if (profile == null || !profile.isActive) {
      await signOut();
      throw const AuthException('This employee account is not active.');
    }
    await PushNotificationService.instance.registerCurrentDevice();
    return profile;
  }

  Future<AppUser?> loadCurrentProfile({bool forceRefresh = false}) async {
    final user = currentAuthUser;
    if (user == null) {
      _cachedProfile = null;
      return null;
    }
    if (!forceRefresh && _cachedProfile?.id == user.id) {
      return _cachedProfile;
    }
    final response = await _db
        .from('profiles')
        .select('id, full_name, username, role, is_active')
        .eq('id', user.id)
        .single();
    _cachedProfile = AppUser.fromMap(response);
    return _cachedProfile;
  }

  Future<void> signOut() async {
    try {
      await PushNotificationService.instance
          .unregisterCurrentDevice()
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Notification cleanup must never prevent an employee from signing out.
    }
    _cachedProfile = null;
    await _db.auth.signOut(scope: SignOutScope.local);
  }
}
