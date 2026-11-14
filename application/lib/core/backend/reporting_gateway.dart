import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_service.dart';
import '../config/app_config.dart';
import 'report_error.dart';

/// File formats of a report export.
enum ReportFormat {
  xlsx('xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'Excel'),
  pdf('pdf', 'application/pdf', 'PDF');

  const ReportFormat(this.wire, this.mime, this.label);
  final String wire;
  final String mime;
  final String label;
}

/// The two data exports. Only [fullZip] can be restored (by the command-line script); [csvZip] is for spreadsheets.
enum BackupKind { fullZip, csvZip }

/// A file saved on this phone.
class DownloadedFile {
  const DownloadedFile({required this.path, required this.sizeBytes, required this.fileName});

  final String path;
  final int sizeBytes;
  final String fileName;
}

/// Answer of `POST /backup/validate`.
class BackupValidation {
  const BackupValidation({required this.ok, required this.errors, required this.warnings, required this.counts, this.exportedAt, this.formatVersion, this.mediaIncluded});

  final bool ok;
  final List<String> errors;
  final List<String> warnings;

  /// Rows per table found in the backup.
  final Map<String, int> counts;
  final DateTime? exportedAt;
  final int? formatVersion;
  final bool? mediaIncluded;

  int get totalRows => counts.values.fold(0, (a, b) => a + b);

  factory BackupValidation.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? v) => v is List ? [for (final e in v) '$e'] : const [];
    final counts = <String, int>{};
    final raw = json['counts'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final v = e.value;
        if (v is num) counts['${e.key}'] = v.toInt();
      }
    }
    final at = json['exported_at'];
    final version = json['format_version'];
    final media = json['media_included'];
    return BackupValidation(
      ok: json['ok'] == true,
      errors: strings(json['errors']),
      warnings: strings(json['warnings']),
      counts: counts,
      exportedAt: at is String ? DateTime.tryParse(at) : null,
      formatVersion: version is num ? version.toInt() : null,
      mediaIncluded: media is bool ? media : null,
    );
  }
}

typedef DownloadProgress = void Function(int received, int? total);

/// The calls to the reporting service (Stage 5, FastAPI). Read-only: nothing here changes data on the server.
/// Implementations throw [ReportError]. [query] holds the period parameters exactly as the service names them
/// (`period`, `year`, `month`, ..., `compare`).
abstract class ReportingGateway {
  /// `GET /api/v1/reports/summary`. Returns the JSON object.
  Future<Map<String, dynamic>> summary(Map<String, String> query);

  /// `GET /api/v1/reports/export`. Saves the file in [directory] and returns it.
  Future<DownloadedFile> downloadReport({required Map<String, String> query, required ReportFormat format, required String directory, DownloadProgress? onProgress});

  /// `GET /api/v1/backup/export` (zip) or `?format=csv`. [includeMedia] only applies to the full backup.
  Future<DownloadedFile> downloadBackup({required BackupKind kind, bool includeMedia = false, required String directory, DownloadProgress? onProgress});

  /// `POST /api/v1/backup/validate` with the file as multipart field `file`.
  Future<BackupValidation> validateBackup(String filePath);
}

/// Used when `REPORT_API_URL` is not set in the build: every call says so.
class NotConfiguredReportingGateway implements ReportingGateway {
  const NotConfiguredReportingGateway([this.why]);

  final String? why;

  ReportError get _error => ReportError.notConfigured(why == null ? null : 'The reporting service is not set up in this build. $why');

  @override
  Future<Map<String, dynamic>> summary(Map<String, String> query) => Future.error(_error);

  @override
  Future<DownloadedFile> downloadReport({required Map<String, String> query, required ReportFormat format, required String directory, DownloadProgress? onProgress}) => Future.error(_error);

  @override
  Future<DownloadedFile> downloadBackup({required BackupKind kind, bool includeMedia = false, required String directory, DownloadProgress? onProgress}) => Future.error(_error);

  @override
  Future<BackupValidation> validateBackup(String filePath) => Future.error(_error);
}

/// Gives the owner's access token, refreshed when [force] is set.
typedef AccessTokenSource = Future<String?> Function({bool force});

/// [ReportingGateway] over HTTP. Sends `Authorization: Bearer <token>`; after a 401 it refreshes the token and tries once more.
class HttpReportingGateway implements ReportingGateway {
  HttpReportingGateway({
    required this.baseUrl,
    required this.token,
    http.Client? client,
    this.summaryTimeout = const Duration(seconds: 45),
    this.exportTimeout = const Duration(minutes: 3),
    this.backupTimeout = const Duration(minutes: 10),
    this.idleTimeout = const Duration(seconds: 90),
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final AccessTokenSource token;
  final http.Client _client;

  /// How long the service may take to start answering (report generation happens before the answer starts).
  final Duration summaryTimeout;
  final Duration exportTimeout;
  final Duration backupTimeout;

  /// How long a download may stall between two pieces of data.
  final Duration idleTimeout;

  Uri _uri(List<String> segments, [Map<String, String>? query]) {
    final base = [for (final s in baseUrl.pathSegments) if (s.isNotEmpty) s];
    return baseUrl.replace(pathSegments: [...base, 'api', 'v1', ...segments], queryParameters: (query == null || query.isEmpty) ? null : query);
  }

  /// Sends a request built by [build] with the token. Rebuilds and retries once after a 401.
  Future<http.StreamedResponse> _send(Future<http.BaseRequest> Function() build, Duration timeout) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final bearer = await token(force: attempt == 1);
      if (bearer == null || bearer.isEmpty) {
        throw const ReportError(ReportErrorKind.unauthorized, 'You are signed out. Sign in again to use reports.');
      }
      final request = await build();
      request.headers['Authorization'] = 'Bearer $bearer';
      final response = await _client.send(request).timeout(timeout);
      if (response.statusCode == 401 && attempt == 0) {
        await response.stream.drain<void>();
        continue;
      }
      return response;
    }
    throw const ReportError(ReportErrorKind.unauthorized, 'The reporting service did not accept this sign-in. Sign out and sign in again.', statusCode: 401);
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on ReportError {
      rethrow;
    } on TimeoutException {
      throw const ReportError(ReportErrorKind.timeout, 'The reporting service took too long to answer. Try again.');
    } on SocketException {
      throw const ReportError(ReportErrorKind.unreachable, 'Cannot reach the reporting service. Check your connection and that the service is running.');
    } on HandshakeException {
      throw const ReportError(ReportErrorKind.unreachable, 'Could not make a secure connection to the reporting service.');
    } on http.ClientException {
      throw const ReportError(ReportErrorKind.unreachable, 'Cannot reach the reporting service. Check your connection and that the service is running.');
    } on FileSystemException catch (e) {
      throw ReportError(ReportErrorKind.fileProblem, 'The file could not be saved or read on this phone${e.osError == null ? '' : ' (${e.osError!.message})'}.');
    } on FormatException {
      throw const ReportError(ReportErrorKind.badResponse, 'The reporting service sent an answer the app could not read.');
    }
  }

  Future<http.BaseRequest> Function() _get(Uri uri) => () async => http.Request('GET', uri);

  @override
  Future<Map<String, dynamic>> summary(Map<String, String> query) => _guard(() async {
        final streamed = await _send(_get(_uri(['reports', 'summary'], query)), summaryTimeout);
        final response = await http.Response.fromStream(streamed).timeout(idleTimeout);
        if (response.statusCode != 200) throw ReportError.fromResponse(response.statusCode, utf8.decode(response.bodyBytes, allowMalformed: true));
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map) throw const ReportError(ReportErrorKind.badResponse, 'The reporting service sent an answer the app could not read.');
        return Map<String, dynamic>.from(decoded);
      });

  @override
  Future<DownloadedFile> downloadReport({required Map<String, String> query, required ReportFormat format, required String directory, DownloadProgress? onProgress}) =>
      _guard(() => _download(_uri(['reports', 'export'], {...query, 'format': format.wire}), exportTimeout, directory, 'fitness-report.${format.wire}', onProgress));

  @override
  Future<DownloadedFile> downloadBackup({required BackupKind kind, bool includeMedia = false, required String directory, DownloadProgress? onProgress}) => _guard(() {
        final query = <String, String>{
          if (kind == BackupKind.csvZip) 'format': 'csv',
          if (kind == BackupKind.fullZip && includeMedia) 'include_media': 'true',
        };
        return _download(_uri(['backup', 'export'], query), backupTimeout, directory, kind == BackupKind.csvZip ? 'fitness-export.zip' : 'fitness-backup.zip', onProgress);
      });

  Future<DownloadedFile> _download(Uri uri, Duration timeout, String directory, String fallbackName, DownloadProgress? onProgress) async {
    final streamed = await _send(_get(uri), timeout);
    if (streamed.statusCode != 200) {
      final body = await http.Response.fromStream(streamed).timeout(idleTimeout);
      throw ReportError.fromResponse(streamed.statusCode, utf8.decode(body.bodyBytes, allowMalformed: true));
    }
    final dir = Directory(directory);
    await dir.create(recursive: true);
    final name = uniqueName(dir, safeFileName(fileNameFromDisposition(streamed.headers['content-disposition']) ?? fallbackName, fallbackName));
    final target = File('${dir.path}${Platform.pathSeparator}$name');
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream.timeout(idleTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, streamed.contentLength);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      if (await part.exists()) await part.delete();
      rethrow;
    }
    if (received == 0) {
      if (await part.exists()) await part.delete();
      throw const ReportError(ReportErrorKind.badResponse, 'The reporting service sent an empty file.');
    }
    await part.rename(target.path);
    return DownloadedFile(path: target.path, sizeBytes: received, fileName: name);
  }

  @override
  Future<BackupValidation> validateBackup(String filePath) => _guard(() async {
        final file = File(filePath);
        if (!await file.exists()) throw const ReportError(ReportErrorKind.fileProblem, 'That file is no longer on this phone.');
        final streamed = await _send(() async {
          final request = http.MultipartRequest('POST', _uri(['backup', 'validate']));
          request.files.add(await http.MultipartFile.fromPath('file', filePath));
          return request;
        }, backupTimeout);
        final response = await http.Response.fromStream(streamed).timeout(backupTimeout);
        if (response.statusCode != 200) throw ReportError.fromResponse(response.statusCode, utf8.decode(response.bodyBytes, allowMalformed: true));
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map) throw const ReportError(ReportErrorKind.badResponse, 'The reporting service sent an answer the app could not read.');
        return BackupValidation.fromJson(Map<String, dynamic>.from(decoded));
      });

  /// `filename="x.pdf"` from a Content-Disposition header, or null.
  static String? fileNameFromDisposition(String? header) {
    if (header == null) return null;
    final m = RegExp(r'filename\*?=(?:UTF-8\x27\x27)?"?([^";]+)"?', caseSensitive: false).firstMatch(header);
    return m?.group(1);
  }

  /// Keeps only characters that are safe in a file name, and never a path.
  static String safeFileName(String name, String fallback) {
    final base = name.split(RegExp(r'[\\/]')).last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_').replaceAll(RegExp(r'^\.+'), '');
    return base.isEmpty ? fallback : base;
  }

  /// [name], or `name-1.ext`, `name-2.ext` ... when a file of that name exists, so an earlier export is never overwritten.
  static String uniqueName(Directory dir, String name) {
    if (!File('${dir.path}${Platform.pathSeparator}$name').existsSync()) return name;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 1; i < 1000; i++) {
      final candidate = '$stem-$i$ext';
      if (!File('${dir.path}${Platform.pathSeparator}$candidate').existsSync()) return candidate;
    }
    return '$stem-${DateTime.now().millisecondsSinceEpoch}$ext';
  }
}

/// The gateway the app uses. Built from `REPORT_API_URL`; tests override it. Without a valid address every call
/// says the service is not set up, and the rest of the app is unaffected.
final reportingGatewayProvider = Provider<ReportingGateway>((ref) {
  final check = AppConfig.checkReportUrl(AppConfig.reportApiUrl);
  final base = check.baseUrl;
  if (base == null) return NotConfiguredReportingGateway(check.problem);
  final auth = ref.read(authServiceProvider);
  return HttpReportingGateway(baseUrl: base, token: ({bool force = false}) => auth.accessToken(forceRefresh: force));
});

/// True when this build knows where the reporting service is (the address is valid).
final reportingConfiguredProvider = Provider<bool>((ref) => ref.watch(reportingGatewayProvider) is! NotConfiguredReportingGateway);
