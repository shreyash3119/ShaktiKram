import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

/// Supabase Auth implementation. The session is saved by supabase_flutter and restored at start,
/// so the owner signs in once per device (decision D3).
class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._auth);

  final GoTrueClient _auth;

  @override
  bool get hasSession => _auth.currentSession != null;

  @override
  String? get email => _auth.currentUser?.email;

  @override
  Stream<bool> get signedInChanges => _auth.onAuthStateChange.map((state) => state.session != null).distinct();

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithPassword(email: email, password: password);
    } on AuthRetryableFetchException {
      throw const AuthFailure(AuthFailureKind.network);
    } on AuthException catch (e) {
      if (e.code == 'invalid_credentials' || e.statusCode == '400') {
        throw const AuthFailure(AuthFailureKind.invalidCredentials);
      }
      throw AuthFailure(AuthFailureKind.unknown, e.message);
    } catch (_) {
      throw const AuthFailure(AuthFailureKind.network);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<String?> accessToken({bool forceRefresh = false}) async {
    var session = _auth.currentSession;
    if (session == null) return null;
    final expiresAt = session.expiresAt;
    final nearExpiry = expiresAt != null && DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000).isBefore(DateTime.now().add(const Duration(seconds: 60)));
    if (forceRefresh || session.isExpired || nearExpiry) {
      try {
        final refreshed = await _auth.refreshSession();
        session = refreshed.session ?? _auth.currentSession;
      } catch (_) {
        // The refresh could not be done (offline, or the refresh token was rejected). Use what is stored unless it has expired.
        session = _auth.currentSession;
        if (session == null || session.isExpired) return null;
      }
    }
    return session?.accessToken;
  }
}
