/// An error from the backend, using the codes in `shared/api_contracts/error_codes.json`.
///
/// The server raises errors with the code as a message prefix, for example
/// `device_revoked: this device was revoked` (known gap: not the contract's JSON envelope).
class BackendError implements Exception {
  const BackendError(this.code, this.message);

  /// Cannot reach the server. Uses the contract code `unavailable`.
  const BackendError.unreachable() : this('unavailable', 'Cannot reach the server.');

  final String code;
  final String message;

  static final _prefix = RegExp(r'^([a-z][a-z_]*):\s*(.*)$', dotAll: true);

  /// Reads `code: text` messages. [httpCode] is the PostgREST code such as `PT401`, used when there is no prefix.
  factory BackendError.fromRaw({String? httpCode, required String message}) {
    final match = _prefix.firstMatch(message.trim());
    if (match != null) return BackendError(match.group(1)!, match.group(2)!);
    switch (httpCode) {
      case 'PT401':
      case 'PGRST301':
      case 'PGRST303':
        return BackendError('unauthorized', message);
      case 'PT403':
        return BackendError('device_revoked', message);
      case 'PT404':
        return BackendError('not_found', message);
      case 'PT413':
        return BackendError('payload_too_large', message);
      case 'PT422':
        return BackendError('validation_failed', message);
    }
    return BackendError('internal_error', message);
  }

  bool get isUnreachable => code == 'unavailable';
  bool get isDeviceRevoked => code == 'device_revoked';
  bool get isNotOwner => code == 'unauthorized' && message.contains('already has an owner');

  /// Wording for the screen.
  String get userMessage {
    switch (code) {
      case 'unavailable':
        return 'Cannot reach the server. Check your connection and try again.';
      case 'unauthorized':
        return 'The server did not accept this sign-in. Sign out and sign in again.';
      case 'device_revoked':
        return 'This device was removed from your account.';
      case 'validation_failed':
        return message;
      default:
        return 'Something went wrong ($code). Try again.';
    }
  }

  @override
  String toString() => 'BackendError($code: $message)';
}
