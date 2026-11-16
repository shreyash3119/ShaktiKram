import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/reporting_gateway.dart';
import '../../../core/db/export_log.dart';
import '../../../core/errors/user_facing_error.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../data/export_service.dart';
import '../data/report_period.dart';
import 'report_format.dart';

String errorText(Object e) =>
    e is UserFacingError ? e.message : 'Something went wrong: $e';

String whenText(DateTime t) {
  final d = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// The Export tab: Excel and PDF for the period chosen above, the way to the backup screen, and the files saved here.
class ExportTab extends ConsumerStatefulWidget {
  const ExportTab({super.key, required this.request});
  final ReportRequest request;

  @override
  ConsumerState<ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends ConsumerState<ExportTab> {
  ReportFormat? _busy;
  double? _progress;
  String? _error;
  ExportLogEntry? _done;

  Future<void> _export(ReportFormat format) async {
    setState(() {
      _busy = format;
      _progress = null;
      _error = null;
      _done = null;
    });
    try {
      final entry = await ref
          .read(exportServiceProvider)
          .exportReport(
            widget.request,
            format,
            onProgress: (got, total) {
              if (mounted && total != null && total > 0) {
                setState(() => _progress = got / total);
              }
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

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final query = widget.request.query;
    final problem = query.validate();
    final configured = ref.watch(reportingConfiguredProvider);
    final busy = _busy != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TitledCard(
          title: 'Export a report',
          children: [
            MutedText(
              widget.request.compare
                  ? 'Period: ${query.label}, with a comparison to the previous period. Change it above.'
                  : 'Period: ${query.label}. Change it above.',
              size: 16,
            ),
            const SizedBox(height: 14),
            if (!configured)
              const MutedText(
                'Exports need the reporting service. This build has no REPORT_API_URL.',
              )
            else if (problem != null)
              MutedText(problem)
            else ...[
              AppButton.primary(
                busy && _busy == ReportFormat.xlsx
                    ? 'Preparing Excel…'
                    : 'Download Excel (.xlsx)',
                height: 58,
                onPressed: busy ? null : () => _export(ReportFormat.xlsx),
              ),
              const SizedBox(height: 10),
              AppButton(
                busy && _busy == ReportFormat.pdf
                    ? 'Preparing PDF…'
                    : 'Download PDF',
                height: 58,
                onPressed: busy ? null : () => _export(ReportFormat.pdf),
              ),
            ],
            if (busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 4),
              const MutedText(
                'Downloading. Large periods can take a minute.',
                size: 12,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('export-error'),
                style: TextStyle(color: p.red, fontSize: 14),
              ),
            ],
            if (_done != null) ...[
              const SizedBox(height: 12),
              RowList([
                RowItem(
                  title: 'Saved ${_done!.fileName}',
                  subtitle: fmtBytes(_done!.sizeBytes),
                  trailing: 'Share',
                  onTap: () => shareEntry(context, ref, _done!),
                ),
              ]),
            ],
          ],
        ),
        const SizedBox(height: 16),
        const TitledCard(
          title: 'Saved on this phone',
          children: [ExportHistoryList(reportsOnly: true)],
        ),
        const SizedBox(height: 16),
        TitledCard(
          title: 'Backup',
          children: [
            const MutedText(
              'Full backup or CSV export of all your data.',
              size: 16,
            ),
            const SizedBox(height: 14),
            AppButton(
              'Open backup',
              height: 58,
              onPressed: () => context.push(AppRoutes.backup),
            ),
          ],
        ),
      ],
    );
  }
}

String _badge(ExportKind k) {
  switch (k) {
    case ExportKind.reportXlsx:
      return 'XLS';
    case ExportKind.reportPdf:
      return 'PDF';
    case ExportKind.backupZip:
      return 'ZIP';
    case ExportKind.dataCsv:
      return 'CSV';
  }
}

Future<void> shareEntry(
  BuildContext context,
  WidgetRef ref,
  ExportLogEntry entry,
) async {
  final messenger = ScaffoldMessenger.of(context);

  try {
    final exists = await ref.read(exportServiceProvider).fileExists(entry);

    if (!context.mounted) return;

    if (!exists) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That file is no longer on this phone.')),
      );
      return;
    }

    await ref.read(fileSharerProvider).share(entry.path, subject: entry.label);
  } catch (e) {
    if (!context.mounted) return;

    messenger.showSnackBar(
      SnackBar(content: Text('Could not share the file: $e')),
    );
  }
}

/// Files the app has saved: reports (`reportsOnly`) or backups and CSV exports.
class ExportHistoryList extends ConsumerWidget {
  const ExportHistoryList({super.key, required this.reportsOnly});
  final bool reportsOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final async = ref.watch(exportHistoryProvider);
    return async.when(
      loading:
          () => const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator()),
          ),
      error:
          (e, _) =>
              MutedText('Could not read the saved files: ${errorText(e)}'),
      data: (all) {
        final items = [
          for (final e in all)
            if (e.kind.isReport == reportsOnly) e,
        ];
        if (items.isEmpty) {
          return MutedText(
            reportsOnly
                ? 'No reports saved yet.'
                : 'No backups or data exports saved yet.',
          );
        }
        return RowList([
          for (final e in items)
            InkWell(
              onTap: () => _options(context, ref, e),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.tile,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _badge(e.kind),
                        style: TextStyle(
                          color: p.link,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.label,
                            style: TextStyle(
                              color: p.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${whenText(e.createdAt).substring(0, 10)} · ${fmtBytes(e.sizeBytes)}',
                            style: TextStyle(color: p.muted, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.more_vert,
                      key: Key('file-options-${e.fileName}'),
                      color: p.muted,
                    ),
                  ],
                ),
              ),
            ),
        ]);
      },
    );
  }

  Future<void> _options(
    BuildContext context,
    WidgetRef ref,
    ExportLogEntry entry,
  ) async {
    final exists = await ref.read(exportServiceProvider).fileExists(entry);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder:
          (sheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.fileName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  MutedText(
                    exists
                        ? 'Saved inside the app on this phone.'
                        : 'The file is no longer on this phone. You can remove the record.',
                  ),
                  const SizedBox(height: 14),
                  if (exists) ...[
                    AppButton.primary(
                      'Share or open',
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        shareEntry(context, ref, entry);
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  AppButton(
                    exists ? 'Delete file' : 'Remove record',
                    kind: ButtonKind.danger,
                    onPressed: () async {
                      Navigator.of(sheet).pop();
                      await ref.read(exportServiceProvider).delete(entry);
                      ref.invalidate(exportHistoryProvider);
                    },
                  ),
                ],
              ),
            ),
          ),
    );
  }
}
