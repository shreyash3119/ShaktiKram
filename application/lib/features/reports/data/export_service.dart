import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/backend/report_error.dart';
import '../../../core/backend/reporting_gateway.dart';
import '../../../core/db/export_log.dart';
import '../../../core/db/local_store.dart';
import 'report_period.dart';

/// Opens the phone's share sheet for a saved file (which is also how it is opened in another app).
abstract class FileSharer {
  Future<void> share(String path, {String? mime, String? subject});
}

class SharePlusFileSharer implements FileSharer {
  const SharePlusFileSharer();

  @override
  Future<void> share(String path, {String? mime, String? subject}) async {
    await Share.shareXFiles([XFile(path, mimeType: mime)], subject: subject);
  }
}

/// Lets the person choose a backup file on the phone.
abstract class BackupFilePicker {
  /// The path of the chosen `.zip` file, or null when nothing was chosen.
  Future<String?> pickBackupZip();
}

class SystemBackupFilePicker implements BackupFilePicker {
  const SystemBackupFilePicker();

  @override
  Future<String?> pickBackupZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: false,
    );
    final files = result?.files;
    if (files == null || files.isEmpty) return null;
    return files.first.path;
  }
}

/// Folder where exported files are kept (inside the app's own storage).
typedef ExportDirectory = Future<String> Function();

/// Downloads reports and backups from the reporting service, saves them on the phone and keeps a local history.
/// Nothing here writes to the server and nothing goes through the outbox.
class ExportService {
  ExportService({
    required LocalStore store,
    required ReportingGateway gateway,
    required ExportDirectory directory,
    DateTime Function()? clock,
  }) : _store = store,
       _gateway = gateway,
       _directory = directory,
       _clock = clock ?? DateTime.now;

  final LocalStore _store;
  final ReportingGateway _gateway;
  final ExportDirectory _directory;
  final DateTime Function() _clock;

  /// Downloads the report for [request] as [format] and records it in the history.
  Future<ExportLogEntry> exportReport(
    ReportRequest request,
    ReportFormat format, {
    DownloadProgress? onProgress,
  }) async {
    final problem = request.query.validate();
    if (problem != null){
      throw ReportError(ReportErrorKind.invalidRequest, problem);}
    final file = await _gateway.downloadReport(
      query: request.toParams(),
      format: format,
      directory: await _directory(),
      onProgress: onProgress,
    );
    return _store.addExportLog(
      ExportLogEntry(
        kind:
            format == ReportFormat.xlsx
                ? ExportKind.reportXlsx
                : ExportKind.reportPdf,
        label: request.query.label,
        path: file.path,
        sizeBytes: file.sizeBytes,
        createdAt: _clock(),
        detail: {'period': request.query.kind.wire, 'compare': request.compare},
      ),
    );
  }

  /// Downloads the full backup or the CSV data export and records it in the history.
  Future<ExportLogEntry> exportBackup(
    BackupKind kind, {
    bool includeMedia = false,
    DownloadProgress? onProgress,
  }) async {
    final withMedia = kind == BackupKind.fullZip && includeMedia;
    final file = await _gateway.downloadBackup(
      kind: kind,
      includeMedia: withMedia,
      directory: await _directory(),
      onProgress: onProgress,
    );
    return _store.addExportLog(
      ExportLogEntry(
        kind:
            kind == BackupKind.fullZip
                ? ExportKind.backupZip
                : ExportKind.dataCsv,
        label: kind == BackupKind.fullZip ? 'Full backup' : 'CSV data export',
        path: file.path,
        sizeBytes: file.sizeBytes,
        createdAt: _clock(),
        detail: {'include_media': withMedia},
      ),
    );
  }

  /// Sends a backup file to the service to be checked. The service only reads it; nothing is restored.
  Future<BackupValidation> validate(String path) =>
      _gateway.validateBackup(path);

  Future<List<ExportLogEntry>> history({int limit = 100}) =>
      _store.exportLog(limit: limit);

  /// The newest full backup recorded on this phone, or null.
  Future<ExportLogEntry?> lastBackup() async {
    for (final e in await _store.exportLog(limit: 200)) {
      if (e.kind == ExportKind.backupZip) return e;
    }
    return null;
  }

  /// True when the saved file is still on the phone.
  Future<bool> fileExists(ExportLogEntry entry) => File(entry.path).exists();

  /// Removes the file from the phone (if it is still there) and its history record.
  Future<void> delete(ExportLogEntry entry) async {
    final file = File(entry.path);
    if (await file.exists()) await file.delete();
    final id = entry.id;
    if (id != null) await _store.removeExportLog(id);
  }
}

final exportDirectoryProvider = Provider<ExportDirectory>(
  (ref) => () async {
    final base = await getApplicationDocumentsDirectory();
    return p.join(base.path, 'exports');
  },
);

final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService(
    store: ref.read(localStoreProvider),
    gateway: ref.read(reportingGatewayProvider),
    directory: ref.read(exportDirectoryProvider),
  );
});

final fileSharerProvider = Provider<FileSharer>(
  (ref) => const SharePlusFileSharer(),
);
final backupFilePickerProvider = Provider<BackupFilePicker>(
  (ref) => const SystemBackupFilePicker(),
);

/// The files saved on this phone, newest first. Invalidate after an export or a delete.
final exportHistoryProvider = FutureProvider.autoDispose<List<ExportLogEntry>>(
  (ref) => ref.read(exportServiceProvider).history(),
);
