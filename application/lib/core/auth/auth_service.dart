import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AuthFailureKind { invalidCredentials, network, unknown }

/// A failed sign-in, with wording for the screen.
class AuthFailure implements Exception {
  const AuthFailure(this.kind, [this.detail]);

  final AuthFailureKind kind;
  final String? detail;

  String get userMessage {
    switch (kind) {
      case AuthFailureKind.invalidCredentials:
        return 'Email or password is incorrect.';
      case AuthFailureKind.network:
        return 'Cannot reach the server. Check your connection and try again.';
      case AuthFailureKind.unknown:
        return 'Sign-in failed. Try again.';
    }
  }

  @override
  String toString() => 'AuthFailure($kind${detail == null ? '' : ': $detail'})';
}

/// The owner's sign-in session. There is one owner account and no registration (decision D3).
abstract class AuthService {
  /// True when a session is stored on this device, even if its access token has expired.
  bool get hasSession;

  String? get email;

  /// Emits true when a session exists and false when it ends (sign-out or refresh token rejected).
  Stream<bool> get signedInChanges;

  /// Throws [AuthFailure].
  Future<void> signIn({required String email, required String password});

  Future<void> signOut();
}

/// Replaced in `main.dart` (and in tests).
final authServiceProvider = Provider<AuthService>((ref) {
  throw UnimplementedError('authServiceProvider must be overridden');
});
