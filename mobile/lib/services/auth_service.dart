import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/network/api_exception.dart';
import '../core/storage/token_storage.dart';
import '../models/user.dart';

/// Supabase Auth is the sole authentication/session authority.
///
/// Login, logout, and restore never contact the Express backend. The
/// signed-in profile (id/name/email/role) is read directly from
/// public.users under RLS, keyed by auth_user_id = auth.uid().
class AuthService extends ChangeNotifier {
  AuthService({
    required TokenStorage tokenStorage,
  }) : _tokenStorage = tokenStorage;

  final TokenStorage _tokenStorage;

  User? currentUser;
  bool isRestoring = true;

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Restores the session from Supabase's own persisted session.
  Future<void> restore() async {
    try {
      final session = _supabase.auth.currentSession;
      final authUser = session?.user;

      if (authUser == null) {
        currentUser = null;
        return;
      }

      final user = await _loadApplicationUser(authUser.id);
      if (user == null) {
        await _signOutSupabase();
        await _tokenStorage.clear();
        currentUser = null;
        return;
      }

      currentUser = user;
    } catch (_) {
      currentUser = null;
    } finally {
      isRestoring = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    final AuthResponse authResponse;
    try {
      authResponse = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (error) {
      throw ApiException(_statusCode(error), error.message);
    }

    final authUser = authResponse.user;
    if (authResponse.session == null || authUser == null) {
      await _signOutSupabase();
      throw ApiException(0, 'Login did not return a session');
    }

    User? user;
    try {
      user = await _loadApplicationUser(authUser.id);
    } catch (error) {
      await _signOutSupabase();
      await _tokenStorage.clear();
      currentUser = null;
      notifyListeners();
      if (error is ApiException) {
        rethrow;
      }
      throw ApiException(0, 'Login failed. Please try again.');
    }

    if (user == null) {
      await _signOutSupabase();
      await _tokenStorage.clear();
      currentUser = null;
      notifyListeners();
      throw ApiException(401, 'No application user is linked to this account');
    }

    currentUser = user;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _signOutSupabase();
    } finally {
      await _tokenStorage.clear();
      currentUser = null;
      notifyListeners();
    }
  }

  Future<void> handleUnauthorized() async {
    if (currentUser == null) {
      return;
    }
    await logout();
  }

  Future<User?> _loadApplicationUser(String authUserId) async {
    try {
      final row = await _supabase
          .from('users')
          .select('id, name, email, role')
          .eq('auth_user_id', authUserId)
          .maybeSingle();

      if (row == null) {
        return null;
      }
      return User.fromJson(row);
    } on PostgrestException catch (error) {
      throw _asApiException(error);
    }
  }

  Future<void> _signOutSupabase() async {
    try {
      await _supabase.auth.signOut();
    } on AuthException {
      // Local state is still cleared by the caller.
    }
  }

  ApiException _asApiException(PostgrestException error) {
    final code = error.code;
    final message = error.message;

    if (code == '28000' || message.toLowerCase() == 'unauthenticated') {
      return ApiException(401, 'Authentication required');
    }
    if (code == '42501' || message.toLowerCase().contains('row-level security')) {
      return ApiException(403, 'You do not have permission to perform this action');
    }
    return ApiException(400, message);
  }

  int _statusCode(AuthException error) {
    return int.tryParse(error.statusCode ?? '') ?? 401;
  }
}
