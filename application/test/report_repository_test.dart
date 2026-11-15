import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/backend/report_error.dart';
import 'package:shaktikram/core/backend/reporting_gateway.dart';
import 'package:shaktikram/core/db/export_log.dart';
import 'package:shaktikram/core/insights/insight_repository.dart'
    show InsightFreshness;
import 'package:shaktikram/features/reports/data/export_service.dart';
import 'package:shaktikram/features/reports/data/report_period.dart';
import 'package:shaktikram/features/reports/data/report_repository.dart';

import 'support/memory_local_store.dart';
import 'support/report_fixtures.dart';

void main() {
  late MemoryLocalStore store;
  late FakeReportingGateway gateway;
  late DateTime now;
  final request = ReportRequest(ReportQuery.monthly(2026, 11));

  ReportRepository repo() =>
      ReportRepository(store: store, gateway: gateway, clock: () => now);

  setUp(() {
    store = MemoryLocalStore();
    gateway = FakeReportingGateway();
    now = DateTime.utc(2026, 11, 14, 12);
  });

  group('ReportRepository', () {
    test('nothing is cached before the first refresh', () async {
      final snap = await repo().cached(request);
      expect(snap.hasData, isFalse);
      expect(snap.freshness, InsightFreshness.none);
    });

    test(
      'refresh asks the server with the period, saves the answer and returns it as fresh',
      () async {
        final snap = await repo().refresh(
          ReportRequest(ReportQuery.monthly(2026, 11), compare: true),
        );
        expect(gateway.summaryCalls.single, {
          'period': 'monthly',
          'year': '2026',
          'month': '11',
          'compare': 'true',
        });
        expect(snap.hasData, isTrue);
        expect(snap.error, isNull);
        expect(snap.freshness, InsightFreshness.fresh);
        expect(snap.summary!.training.sessions, 2);
        final saved = await store.readInsight(
          'report:summary:period=monthly&year=2026&month=11&compare=true',
        );
        expect(saved, isNotNull);
        expect(jsonDecode(saved!.payload)['period']['label'], 'November 2026');
      },
    );

    test('a saved summary is fresh for 15 minutes, then stale', () async {
      await repo().refresh(request);
      now = now.add(const Duration(minutes: 10));
      expect((await repo().cached(request)).freshness, InsightFreshness.fresh);
      now = now.add(const Duration(minutes: 10));
      final stale = await repo().cached(request);
      expect(stale.freshness, InsightFreshness.stale);
      expect(stale.hasData, isTrue);
    });

    test(
      'each period and comparison choice has its own saved summary',
      () async {
        await repo().refresh(request);
        expect(
          (await repo().cached(
            ReportRequest(ReportQuery.monthly(2026, 11), compare: true),
          )).hasData,
          isFalse,
        );
        expect(
          (await repo().cached(
            ReportRequest(ReportQuery.monthly(2026, 10)),
          )).hasData,
          isFalse,
        );
      },
    );

    test(
      'when the server cannot be reached the saved summary stays, with the error and its age',
      () async {
        await repo().refresh(request);
        gateway.error = const ReportError(
          ReportErrorKind.unreachable,
          'Cannot reach the reporting service.',
        );
        now = now.add(const Duration(hours: 2));
        final snap = await repo().refresh(request);
        expect(snap.hasData, isTrue);
        expect(snap.isOffline, isTrue);
        expect(snap.freshness, InsightFreshness.stale);
        expect(snap.fetchedAt, DateTime.utc(2026, 11, 14, 12));
        expect(
          (await repo().cached(request)).hasData,
          isTrue,
          reason: 'a failed refresh must not erase the saved copy',
        );
      },
    );

    test(
      'with nothing saved, a failure returns no data and the error',
      () async {
        gateway.error = const ReportError(
          ReportErrorKind.serviceUnavailable,
          'not ready',
        );
        final snap = await repo().refresh(request);
        expect(snap.hasData, isFalse);
        expect(snap.error!.kind, ReportErrorKind.serviceUnavailable);
        expect(snap.isOffline, isFalse);
      },
    );

    test('an invalid period never reaches the server', () async {
      final bad = ReportRequest(
        ReportQuery.custom(DateTime(2026, 2, 1), DateTime(2026, 1, 1)),
      );
      final snap = await repo().refresh(bad);
      expect(gateway.summaryCalls, isEmpty);
      expect(snap.error!.kind, ReportErrorKind.invalidRequest);
    });

    test(
      'an answer that is not a summary is a bad response and is not saved',
      () async {
        gateway.result = {'hello': 'world'};
        final snap = await repo().refresh(request);
        expect(snap.error!.kind, ReportErrorKind.badResponse);
        expect(snap.hasData, isFalse);
        expect(await store.readInsight(request.cacheKey), isNull);
      },
    );

    test(
      'an unreadable saved copy is treated as missing, not as a crash',
      () async {
        await store.writeInsight(request.cacheKey, '{not json', now);
        expect((await repo().cached(request)).hasData, isFalse);
      },
    );
  });

  group('ExportService', () {
    late Directory dir;
    late ExportService service;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('skx_export_');
      service = ExportService(
        store: store,
        gateway: gateway,
        directory: () async => dir.path,
        clock: () => now,
      );
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('a report is saved and recorded with its period', () async {
      final entry = await service.exportReport(request, ReportFormat.pdf);
      expect(gateway.events, ['report:pdf:monthly']);
      expect(entry.kind, ExportKind.reportPdf);
      expect(entry.label, 'November 2026');
      expect(entry.id, isNotNull);
      expect(File(entry.path).existsSync(), isTrue);
      expect((await service.history()).single.path, entry.path);
    });

    test('an invalid period is refused before any download', () async {
      final bad = ReportRequest(
        ReportQuery.custom(DateTime(2026, 2, 1), DateTime(2026, 1, 1)),
      );
      await expectLater(
        service.exportReport(bad, ReportFormat.xlsx),
        throwsA(isA<ReportError>()),
      );
      expect(gateway.events, isEmpty);
      expect(await service.history(), isEmpty);
    });

    test('a failed download leaves no history entry', () async {
      gateway.error = const ReportError(
        ReportErrorKind.serviceUnavailable,
        'down',
      );
      await expectLater(
        service.exportReport(request, ReportFormat.xlsx),
        throwsA(isA<ReportError>()),
      );
      expect(await service.history(), isEmpty);
    });

    test(
      'lastBackup is the newest full backup, never a CSV export or a report',
      () async {
        expect(await service.lastBackup(), isNull);
        await service.exportBackup(BackupKind.fullZip);
        now = now.add(const Duration(days: 1));
        await service.exportBackup(BackupKind.csvZip);
        now = now.add(const Duration(days: 1));
        await service.exportReport(request, ReportFormat.pdf);
        final last = await service.lastBackup();
        expect(last!.kind, ExportKind.backupZip);
        expect(last.createdAt, DateTime.utc(2026, 11, 14, 12));
      },
    );

    test(
      'media is requested only for a full backup that asked for it',
      () async {
        await service.exportBackup(BackupKind.fullZip);
        await service.exportBackup(BackupKind.fullZip, includeMedia: true);
        await service.exportBackup(BackupKind.csvZip, includeMedia: true);
        expect(gateway.events, [
          'backup:fullZip:media=false',
          'backup:fullZip:media=true',
          'backup:csvZip:media=false',
        ]);
      },
    );

    test('delete removes the file and its record', () async {
      final entry = await service.exportBackup(BackupKind.fullZip);
      expect(await service.fileExists(entry), isTrue);
      await service.delete(entry);
      expect(File(entry.path).existsSync(), isFalse);
      expect(await service.history(), isEmpty);
    });

    test('a record whose file is gone can still be removed', () async {
      final entry = await service.exportBackup(BackupKind.fullZip);
      File(entry.path).deleteSync();
      expect(await service.fileExists(entry), isFalse);
      await service.delete(entry);
      expect(await service.history(), isEmpty);
    });

    test(
      'validate passes the file to the service and returns its findings',
      () async {
        gateway.validation = const BackupValidation(
          ok: false,
          errors: ['bad'],
          warnings: ['careful'],
          counts: {'a': 1},
        );
        final v = await service.validate('/tmp/x.zip');
        expect(gateway.events, ['validate:/tmp/x.zip']);
        expect(v.ok, isFalse);
        expect(v.errors, ['bad']);
      },
    );
  });
}
