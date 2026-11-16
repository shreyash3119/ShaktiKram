import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/backend/report_error.dart';
import 'package:shaktikram/core/backend/reporting_gateway.dart';
import 'package:shaktikram/core/db/export_log.dart';
import 'package:shaktikram/core/routing/app_shell.dart';
import 'package:shaktikram/core/sync/sync_status.dart';
import 'package:shaktikram/features/reports/data/export_service.dart';
import 'package:shaktikram/features/reports/data/report_period.dart';
import 'package:shaktikram/features/reports/data/report_repository.dart';

import 'support/fakes.dart';
import 'support/memory_local_store.dart';
import 'support/report_fixtures.dart';

/// An export service that records entries but never touches the disk (file I/O does not finish inside testWidgets).
class _FakeExportService extends ExportService {
  _FakeExportService(this._store, ReportingGateway gateway)
    : super(store: _store, gateway: gateway, directory: () async => '/unused');

  final MemoryLocalStore _store;

  final List<String> calls = [];
  ReportError? failWith;
  BackupValidation? validation;

  Future<ExportLogEntry> _log(ExportKind kind, String label) async {
    final e = failWith;
    if (e != null) throw e;
    return _store.addExportLog(
      ExportLogEntry(
        kind: kind,
        label: label,
        path: '/unused/${kind.wire}.bin',
        sizeBytes: 2048,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<ExportLogEntry> exportReport(
    ReportRequest request,
    ReportFormat format, {
    DownloadProgress? onProgress,
  }) {
    calls.add('report:${format.wire}:${request.query.label}');
    return _log(
      format == ReportFormat.xlsx
          ? ExportKind.reportXlsx
          : ExportKind.reportPdf,
      request.query.label,
    );
  }

  @override
  Future<ExportLogEntry> exportBackup(
    BackupKind kind, {
    bool includeMedia = false,
    DownloadProgress? onProgress,
  }) {
    calls.add('backup:${kind.name}:media=$includeMedia');
    return _log(
      kind == BackupKind.fullZip ? ExportKind.backupZip : ExportKind.dataCsv,
      kind == BackupKind.fullZip ? 'Full backup' : 'CSV data export',
    );
  }

  @override
  Future<BackupValidation> validate(String path) async {
    calls.add('validate:$path');
    return validation ??
        const BackupValidation(
          ok: true,
          errors: [],
          warnings: [],
          counts: {'workout_session': 2},
        );
  }

  @override
  Future<bool> fileExists(ExportLogEntry entry) async => true;

  @override
  Future<void> delete(ExportLogEntry entry) async {}
}

class _FixedSync extends SyncStatusNotifier {
  _FixedSync(this._value);
  final SyncStatus _value;
  @override
  SyncStatus build() => _value;
}

class _Sharer implements FileSharer {
  final List<String> shared = [];
  @override
  Future<void> share(String path, {String? mime, String? subject}) async =>
      shared.add(path);
}

class _Picker implements BackupFilePicker {
  _Picker(this.path);
  final String? path;
  @override
  Future<String?> pickBackupZip() async => path;
}

class _Setup {
  _Setup({this.query, this.sync, String? pick})
    : harness = Harness.ready(),
      gateway = FakeReportingGateway(),
      picker = _Picker(pick),
      sharer = _Sharer() {
    export = _FakeExportService(harness.local, gateway);
  }

  final ReportQuery? query;
  final SyncStatus? sync;
  final Harness harness;
  final FakeReportingGateway gateway;
  final _Picker picker;
  final _Sharer sharer;
  late final _FakeExportService export;

  List<Override> get overrides => [
    ...harness.overrides,
    reportingGatewayProvider.overrideWithValue(gateway),
    reportQueryProvider.overrideWith(
      (ref) => query ?? ReportQuery.monthly(2026, 11),
    ),
    exportServiceProvider.overrideWithValue(export),
    fileSharerProvider.overrideWithValue(sharer),
    backupFilePickerProvider.overrideWithValue(picker),
    if (sync != null) syncStatusProvider.overrideWith(() => _FixedSync(sync!)),
  ];
}

Future<void> _open(WidgetTester tester, _Setup s, String tab) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      key: ObjectKey(s),
      overrides: s.overrides,
      child: const ShaktiKramApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(AppBottomBar), matching: find.text(tab)),
  );
  await tester.pumpAndSettle();
}

Future<void> _pill(WidgetTester tester, String label) async {
  final target = find.byKey(Key('tab-$label'));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the numbers the server calculated, labelled as such', (
    tester,
  ) async {
    final s = _Setup();
    await _open(tester, s, 'Reports');
    expect(s.gateway.summaryCalls.single, {
      'period': 'monthly',
      'year': '2026',
      'month': '11',
    });
    expect(find.textContaining('Updated'), findsOneWidget);
    expect(find.text('12,450'), findsOneWidget);
    expect(
      find.text('Training volume was 12,450 kg over 2 workouts.'),
      findsOneWidget,
    );
    expect(find.textContaining('not medical advice'), findsOneWidget);
    expect(find.text('Performance overview'), findsNothing);
  });

  testWidgets(
    'the tabs show their own sections, with estimated and self-rated values labelled',
    (tester) async {
      final s = _Setup();
      await _open(tester, s, 'Reports');

      await _pill(tester, 'Workouts');
      expect(find.text('Volume by week'), findsOneWidget);
      expect(find.text('Push Pull Legs'), findsOneWidget);

      await _pill(tester, 'Strength');
      expect(find.text('Bench press'), findsWidgets);
      expect(find.textContaining('Estimated values'), findsOneWidget);
      expect(find.text('Personal records'), findsOneWidget);

      await _pill(tester, 'Body');
      expect(find.text('Waist'), findsOneWidget);
      expect(find.textContaining('Your own ratings'), findsOneWidget);
      expect(find.textContaining('professional'), findsOneWidget);

      await _pill(tester, 'Lifestyle');
      expect(find.text('Creatine'), findsOneWidget);

      await _pill(tester, 'Goals');
      expect(find.text('Bench 100 kg'), findsWidgets);
      expect(find.text('Reached'), findsOneWidget);
      expect(
        s.gateway.summaryCalls,
        hasLength(1),
        reason: 'switching tabs must not call the service again',
      );
    },
  );

  testWidgets('comparison is asked for and shown only when switched on', (
    tester,
  ) async {
    final s = _Setup();
    await _open(tester, s, 'Reports');
    expect(find.textContaining('Compared with'), findsNothing);
    s.gateway.result = summaryJson(compare: true);
    await _tap(tester, find.byType(Switch));
    expect(s.gateway.summaryCalls.last['compare'], 'true');
    expect(find.text('Compared with October 2026'), findsOneWidget);
    expect(find.text('-50%'), findsOneWidget);
    expect(find.text('+24.5%'), findsOneWidget);
  });

  testWidgets(
    'stepping to the previous period loads that period; the next period is blocked once it would be in the future',
    (tester) async {
      final s = _Setup();
      await _open(tester, s, 'Reports');
      await tester.tap(find.byKey(const Key('period-prev')));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      expect(s.gateway.summaryCalls.last['month'], '10');

      final s2 = _Setup(query: ReportQuery.monthly(2099, 11));
      await _open(tester, s2, 'Reports');
      final nextPeriod = ReportQuery.monthly(2099, 11).shifted(1);

      expect(nextPeriod.label, 'December 2099');
      expect(nextPeriod.startsAfter(DateTime.now()), isTrue);

      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('period-next')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('a period that has not started says so and asks for nothing', (
    tester,
  ) async {
    final s = _Setup(query: ReportQuery.yearly(2099));
    await _open(tester, s, 'Reports');
    expect(find.text('This period has not started'), findsOneWidget);
    expect(s.gateway.summaryCalls, isEmpty);
  });

  testWidgets('a period with no records says so plainly', (tester) async {
    final s = _Setup();
    s.gateway.result = {
      'period': {
        'kind': 'monthly',
        'label': 'November 2026',
        'start': '2026-11-01',
        'end': '2026-11-30',
        'days': 30,
      },
      'training': {
        'sessions': 0,
        'volume_kg': 0,
        'working_sets': 0,
        'total_reps': 0,
        'weekly': [],
        'attendance': {},
      },
    };
    await _open(tester, s, 'Reports');
    expect(
      find.textContaining('No records were found in this period'),
      findsOneWidget,
    );
    await _pill(tester, 'Strength');
    expect(
      find.textContaining('No finished workouts with logged sets'),
      findsWidgets,
    );
  });

  testWidgets('offline with a saved report keeps showing it, with its age', (
    tester,
  ) async {
    final s = _Setup();
    await s.harness.local.writeInsight(
      'report:summary:period=monthly&year=2026&month=11',
      jsonEncode(summaryJson()),
      DateTime.now().subtract(const Duration(hours: 3)),
    );
    s.gateway.error = const ReportError(
      ReportErrorKind.unreachable,
      'Cannot reach the reporting service.',
    );
    await _open(tester, s, 'Reports');
    expect(find.text('12,450'), findsOneWidget);
    expect(
      find.textContaining('Offline. Showing the report from 3 h ago'),
      findsOneWidget,
    );
  });

  testWidgets(
    'offline with nothing saved says the report is not on this phone yet',
    (tester) async {
      final s = _Setup();
      s.gateway.error = const ReportError(
        ReportErrorKind.unreachable,
        'Cannot reach the reporting service.',
      );
      await _open(tester, s, 'Reports');
      expect(find.text('You are offline'), findsOneWidget);
    },
  );

  testWidgets('a server error is shown with its message', (tester) async {
    final s = _Setup();
    s.gateway.error = const ReportError(
      ReportErrorKind.notOwner,
      'This account is not the owner account, so it cannot use reports or backups.',
    );
    await _open(tester, s, 'Reports');
    expect(find.textContaining('not the owner account'), findsWidgets);
  });

  testWidgets('changes that have not synced are called out', (tester) async {
    final s = _Setup(
      sync: const SyncStatus(SyncPhase.pending, pendingCount: 3),
    );
    await _open(tester, s, 'Reports');
    expect(
      find.text('3 changes on this phone have not synced yet'),
      findsOneWidget,
    );
    expect(find.textContaining('do not include these changes'), findsOneWidget);
  });

  testWidgets('no notice when everything is synced', (tester) async {
    final s = _Setup();
    await _open(tester, s, 'Reports');
    expect(find.textContaining('have not synced yet'), findsNothing);
  });

  testWidgets(
    'the Export tab downloads Excel and PDF and lists what was saved',
    (tester) async {
      final s = _Setup();
      await _open(tester, s, 'Reports');
      await _pill(tester, 'Export');
      expect(find.text('No reports saved yet.'), findsOneWidget);
      expect(find.text('Export category'), findsNothing);

      await _tap(tester, find.text('Download Excel (.xlsx)'));
      await _tap(tester, find.text('Download PDF'));
      expect(s.export.calls, [
        'report:xlsx:November 2026',
        'report:pdf:November 2026',
      ]);
      expect(find.text('XLS'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);

      await _tap(tester, find.textContaining('Saved report_pdf.bin').first);
      expect(s.sharer.shared.single, '/unused/report_pdf.bin');
    },
  );

  testWidgets('an export that fails shows why and saves nothing', (
    tester,
  ) async {
    final s = _Setup();
    s.export.failWith = const ReportError(
      ReportErrorKind.serviceUnavailable,
      'The reporting service is not ready: Report generation failed',
    );
    await _open(tester, s, 'Reports');
    await _pill(tester, 'Export');
    await _tap(tester, find.text('Download PDF'));
    expect(find.byKey(const Key('export-error')), findsOneWidget);
    expect(find.textContaining('Report generation failed'), findsOneWidget);
    expect(find.text('No reports saved yet.'), findsOneWidget);
  });

  testWidgets('Settings: honest backup wording and working links', (
    tester,
  ) async {
    final s = _Setup();
    await _open(tester, s, 'Settings');
    expect(find.textContaining('Local backup, not cloud sync'), findsNothing);
    expect(find.textContaining('Auto-backup'), findsNothing);
    expect(find.text('Restore…'), findsNothing);
    expect(find.textContaining('never made automatically'), findsOneWidget);

    await _tap(tester, find.text('Data & sync'));
    await _tap(tester, find.text('Export data'));
    expect(find.text('Export a report'), findsOneWidget);
  });

  testWidgets(
    'Backup screen: full backup, CSV export and the restore explanation',
    (tester) async {
      final s = _Setup();
      await _open(tester, s, 'Settings');
      await _tap(tester, find.text('Data & sync'));
      await _tap(tester, find.text('Backup & data export'));

      expect(find.byKey(const Key('last-backup')), findsOneWidget);
      expect(
        find.text('No backup has been made from this phone yet.'),
        findsOneWidget,
      );
      expect(
        tester.widget<Switch>(find.byType(Switch)).value,
        isFalse,
        reason: 'media is off by default',
      );
      expect(find.textContaining('not confirmed to work'), findsOneWidget);
      expect(find.text('Restore…'), findsNothing);
      expect(find.textContaining('cannot restore a backup'), findsOneWidget);
      expect(find.textContaining('restore_backup.py'), findsOneWidget);
      expect(
        find.textContaining('not a backup: it cannot be restored'),
        findsOneWidget,
      );

      await _tap(tester, find.text('Make a full backup'));
      expect(s.export.calls, ['backup:fullZip:media=false']);
      expect(
        find.textContaining('Last backup made from this phone:'),
        findsOneWidget,
      );

      await _tap(tester, find.text('Export data as CSV'));
      expect(s.export.calls.last, 'backup:csvZip:media=false');
    },
  );

  testWidgets('Backup screen: turning media on is passed to the backup', (
    tester,
  ) async {
    final s = _Setup();
    await _open(tester, s, 'Settings');
    await _tap(tester, find.text('Data & sync'));
      await _tap(tester, find.text('Backup & data export'));
    await _tap(tester, find.byType(Switch));
    await _tap(tester, find.text('Make a full backup'));
    expect(s.export.calls.single, 'backup:fullZip:media=true');
  });

  testWidgets(
    'Backup screen: a checked file shows its verdict, warnings, errors and counts',
    (tester) async {
      final s = _Setup(pick: '/phone/fitness-backup.zip');
      s.export.validation = BackupValidation(
        ok: false,
        errors: const ['Missing table: exercise'],
        warnings: const ['Media not included'],
        counts: const {'workout_session': 3, 'exercise': 0},
        exportedAt: DateTime.utc(2026, 11, 14, 10),
        formatVersion: 1,
        mediaIncluded: false,
      );
      await _open(tester, s, 'Settings');
      await _tap(tester, find.text('Data & sync'));
      await _tap(tester, find.text('Backup & data export'));
      await _tap(tester, find.text('Choose a file to check'));

      expect(s.export.calls.single, 'validate:/phone/fitness-backup.zip');
      expect(find.text('This backup has problems'), findsOneWidget);
      expect(find.text('Missing table: exercise'), findsOneWidget);
      expect(find.text('Media not included'), findsOneWidget);
      expect(find.text('Workout session'), findsOneWidget);
      expect(find.textContaining('3 rows in 2 tables'), findsOneWidget);
      expect(find.textContaining('format 1'), findsOneWidget);
    },
  );

  testWidgets('Backup screen: cancelling the file picker does nothing', (
    tester,
  ) async {
    final s = _Setup();
    await _open(tester, s, 'Settings');
    await _tap(tester, find.text('Data & sync'));
      await _tap(tester, find.text('Backup & data export'));
    await _tap(tester, find.text('Choose a file to check'));
    expect(s.export.calls, isEmpty);
    expect(find.byKey(const Key('validation-verdict')), findsNothing);
  });
}
