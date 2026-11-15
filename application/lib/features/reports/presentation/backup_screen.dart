import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/reporting_gateway.dart';
import '../../../core/db/export_log.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../data/export_service.dart';
import 'export_tab.dart';
import 'report_format.dart';

/// The newest full backup recorded on this phone.
final lastBackupProvider = FutureProvider.autoDispose<ExportLogEntry?>((ref) {
  ref.watch(exportHistoryProvider);
  return ref.read(exportServiceProvider).lastBackup();
});

/// Backup and data export. The service makes the files; the phone saves them, lets you share them and can ask the
/// service to check a backup file. Restoring is not available in the app.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  BackupKind? _busy;
  double? _progress;
  String? _error;
  ExportLogEntry? _done;
  bool _includeMedia = false;

  bool _validating = false;
  String? _validateError;
  String? _validatedFile;
  BackupValidation? _validation;

  Future<void> _export(BackupKind kind) async {
    setState(() {
      _busy = kind;
      _progress = null;
      _error = null;
      _done = null;
    });
    try {
      final entry = await ref
          .read(exportServiceProvider)
          .exportBackup(
            kind,
            includeMedia: _includeMedia,
            onProgress: (got, total) {
              if (mounted && total != null && total > 0){
                setState(() => _progress = got / total);}
            },
          );
      ref.invalidate(exportHistoryProvider);
      if (mounted) setState(() => _done = entry);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _validate() async {
    String? path;
    try {
      path = await ref.read(backupFilePickerProvider).pickBackupZip();
    } catch (e) {
      setState(() => _validateError = 'Could not open the file picker: $e');
      return;
    }
    if (path == null || !mounted) return;
    setState(() {
      _validating = true;
      _validateError = null;
      _validation = null;
      _validatedFile = path!.split(RegExp(r'[\\/]')).last;
    });
    try {
      final result = await ref.read(exportServiceProvider).validate(path);
      if (mounted) setState(() => _validation = result);
    } catch (e) {
      if (mounted) setState(() => _validateError = errorText(e));
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final configured = ref.watch(reportingConfiguredProvider);
    final last = ref.watch(lastBackupProvider).valueOrNull;
    final busy = _busy != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & data export')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.pagePadding),
          children: [
            TitledCard(
              title: 'Full backup',
              children: [
                Text(
                  last == null
                      ? 'No backup has been made from this phone yet.'
                      : 'Last backup made from this phone: ${whenText(last.createdAt)}',
                  key: const Key('last-backup'),
                  style: TextStyle(color: p.text, fontSize: 15),
                ),
                const SizedBox(height: 6),
                const MutedText(
                  'Backups are never made automatically. This date only covers backups made with this app on this phone; it does not know about backups made elsewhere.',
                  size: 13,
                ),
                const SizedBox(height: 12),
                if (!configured)
                  const MutedText(
                    'Backups need the reporting service. This build has no REPORT_API_URL.',
                  )
                else ...[
                  ToggleRow(
                    title: 'Include photos and media',
                    subtitle:
                        'Off by default. Media backup is not confirmed to work yet, so a backup with media may fail.',
                    value: _includeMedia,
                    onChanged:
                        busy
                            ? (_) {}
                            : (v) => setState(() => _includeMedia = v),
                  ),
                  const SizedBox(height: 6),
                  AppButton.primary(
                    _busy == BackupKind.fullZip
                        ? 'Preparing backup…'
                        : 'Make a full backup',
                    onPressed: busy ? null : () => _export(BackupKind.fullZip),
                  ),
                ],
                if (_busy == BackupKind.fullZip) _progressBlock(),
              ],
            ),
            const SizedBox(height: 16),
            TitledCard(
              title: 'CSV data export',
              children: [
                const MutedText(
                  'Your data as spreadsheet files. This is a data export, not a backup: it cannot be restored.',
                ),
                const SizedBox(height: 12),
                AppButton(
                  _busy == BackupKind.csvZip
                      ? 'Preparing CSV…'
                      : 'Export data as CSV',
                  onPressed:
                      (busy || !configured)
                          ? null
                          : () => _export(BackupKind.csvZip),
                ),
                if (_busy == BackupKind.csvZip) _progressBlock(),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('backup-error'),
                style: TextStyle(color: p.red, fontSize: 14),
              ),
            ],
            if (_done != null) ...[
              const SizedBox(height: 12),
              RowList([
                RowItem(
                  title: 'Saved ${_done!.fileName}',
                  subtitle:
                      '${_done!.kind.label} · ${fmtBytes(_done!.sizeBytes)}',
                  trailing: 'Share',
                  onTap: () => shareEntry(context, ref, _done!),
                ),
              ]),
            ],
            const SizedBox(height: 16),
            TitledCard(
              title: 'Check a backup file',
              children: [
                const MutedText(
                  'Choose a backup (.zip). The reporting service reads it and reports what it found. Nothing is changed or restored.',
                ),
                const SizedBox(height: 12),
                AppButton(
                  _validating ? 'Checking…' : 'Choose a file to check',
                  onPressed: (_validating || !configured) ? null : _validate,
                ),
                if (_validating) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (_validateError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _validateError!,
                    key: const Key('validate-error'),
                    style: TextStyle(color: p.red, fontSize: 14),
                  ),
                ],
                if (_validation != null)
                  _ValidationResult(
                    file: _validatedFile ?? '',
                    result: _validation!,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const TitledCard(
              title: 'Saved on this phone',
              children:  [ExportHistoryList(reportsOnly: false)],
            ),
            const SizedBox(height: 16),
            const TitledCard(
              title: 'Restoring a backup',
              children:  [
                MutedText(
                  'The app cannot restore a backup. Restoring replaces data, so it is done on a computer with the restore script in the project (backend/scripts/restore_backup.py), after the backup has been checked here.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressBlock() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: _progress),
        const SizedBox(height: 4),
        const MutedText(
          'Downloading. This can take several minutes for a large backup.',
          size: 12,
        ),
      ],
    ),
  );
}

class _ValidationResult extends StatelessWidget {
  const _ValidationResult({required this.file, required this.result});
  final String file;
  final BackupValidation result;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final counts =
        result.counts.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.ok
                ? 'This backup passed the check'
                : 'This backup has problems',
            key: const Key('validation-verdict'),
            style: TextStyle(
              color: result.ok ? p.green : p.red,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (file.isNotEmpty) MutedText(file, size: 13),
          const SizedBox(height: 8),
          MutedText(
            [
              '${result.totalRows} rows in ${result.counts.length} tables',
              if (result.exportedAt != null)
                'made ${whenText(result.exportedAt!)}',
              if (result.formatVersion != null)
                'format ${result.formatVersion}',
              if (result.mediaIncluded != null)
                result.mediaIncluded! ? 'includes media' : 'no media',
            ].join(' · '),
            size: 13,
          ),
          if (result.errors.isNotEmpty) ...[
            const SizedBox(height: 10),
            const GroupLabel('Errors'),
            for (final e in result.errors)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(e, style: TextStyle(color: p.red, fontSize: 14)),
              ),
          ],
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            const GroupLabel('Warnings'),
            for (final w in result.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(w, style: TextStyle(color: p.amber, fontSize: 14)),
              ),
          ],
          if (counts.isNotEmpty) ...[
            const SizedBox(height: 10),
            const GroupLabel('Rows per table'),
            RowList([
              for (final c in counts)
                RowItem(title: prettyKey(c.key), trailing: '${c.value}'),
            ]),
          ],
          if (result.ok)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: MutedText(
                'Passing the check means the file is complete and readable. It does not restore anything.',
                size: 12,
              ),
            ),
        ],
      ),
    );
  }
}
