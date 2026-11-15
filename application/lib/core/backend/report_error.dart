import 'dart:convert';

import '../errors/user_facing_error.dart';

enum ReportErrorKind {
  /// `REPORT_API_URL` is missing or invalid in this build.
  notConfigured,

  /// No connection, or the service is not running.
  unreachable,
  timeout,

  /// 401: no token or the sign-in was not accepted.
  unauthorized,

  /// 403: a valid account that is not the owner.
  notOwner,

  /// 422: a period value the service refused.
  invalidRequest,

  /// 413.
  tooLarge,

  /// 503: the service is up but not ready (sign-in check or media not configured).
  serviceUnavailable,

  /// Any other 4xx or 5xx.
  server,

  /// The answer could not be read.
  badResponse,

  /// The file could not be saved or read on this phone.
  fileProblem,
}

/// An error from the reporting service (FastAPI). Its messages are written for the person using the app.
/// FastAPI reports problems as `{"detail": "text"}` or, for badly formed values, `{"detail": [{"loc": [...], "msg": "text"}]}`.
class ReportError implements UserFacingError {
  const ReportError(this.kind, this.message, {this.statusCode});

  const ReportError.notConfigured([String? why])
    : this(
        ReportErrorKind.notConfigured,
        why ??
            'The reporting service is not set up in this build. Set REPORT_API_URL and rebuild the app.',
      );

  final ReportErrorKind kind;
  @override
  final String message;
  final int? statusCode;

  /// True when there is simply no connection (so an older saved answer is still the best there is).
  bool get isOffline =>
      kind == ReportErrorKind.unreachable || kind == ReportErrorKind.timeout;

  /// Builds the error for an HTTP answer that was not a success.
  factory ReportError.fromResponse(int status, String body) {
    final detail = detailText(body);
    switch (status) {
      case 401:
        return ReportError(
          ReportErrorKind.unauthorized,
          'The reporting service did not accept this sign-in. Sign out and sign in again.',
          statusCode: status,
        );
      case 403:
        return ReportError(
          ReportErrorKind.notOwner,
          'This account is not the owner account, so it cannot use reports or backups.',
          statusCode: status,
        );
      case 413:
        return ReportError(
          ReportErrorKind.tooLarge,
          'That file is too large for the reporting service.',
          statusCode: status,
        );
      case 422:
        return ReportError(
          ReportErrorKind.invalidRequest,
          detail == null
              ? 'The reporting service did not accept that request.'
              : 'The reporting service did not accept that request: $detail',
          statusCode: status,
        );
      case 503:
        return ReportError(
          ReportErrorKind.serviceUnavailable,
          detail == null
              ? 'The reporting service is not ready yet.'
              : 'The reporting service is not ready: $detail',
          statusCode: status,
        );
      default:
        return ReportError(
          ReportErrorKind.server,
          'The reporting service had a problem ($status). Try again later.',
          statusCode: status,
        );
    }
  }

  /// The text FastAPI put in `detail`, or null.
  static String? detailText(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final detail = decoded['detail'];
      if (detail is String) return detail.trim().isEmpty ? null : detail.trim();
      if (detail is List) {
        final parts = <String>[];
        for (final item in detail) {
          if (item is Map && item['msg'] is String) {
            final loc = item['loc'];
            final where = loc is List && loc.isNotEmpty ? '${loc.last}: ' : '';
            parts.add('$where${item['msg']}');
          } else if (item is String) {
            parts.add(item);
          }
        }
        return parts.isEmpty ? null : parts.join('; ');
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  @override
  String toString() => 'ReportError(${kind.name}: $message)';
}
