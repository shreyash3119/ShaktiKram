import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shaktikram/core/backend/report_error.dart';
import 'package:shaktikram/core/backend/reporting_gateway.dart';

import 'support/report_fixtures.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('skx_gateway_'));
  tearDown(() => dir.deleteSync(recursive: true));

  final base = Uri.parse('https://reports.example.com');

  /// A gateway whose token source hands out `t1`, then `t2` after a forced refresh.
  HttpReportingGateway gateway(MockClient client, {List<bool>? forced, String? Function()? tokenOverride, Duration idle = const Duration(seconds: 5)}) {
    return HttpReportingGateway(
      baseUrl: base,
      client: client,
      idleTimeout: idle,
      token: ({bool force = false}) async {
        forced?.add(force);
        if (tokenOverride != null) return tokenOverride();
        return force ? 't2' : 't1';
      },
    );
  }

  http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  group('summary', () {
    test('calls /api/v1/reports/summary with the period and a bearer token', () async {
      late http.Request seen;
      final g = gateway(MockClient((r) async {
        seen = r;
        return json(summaryJson());
      }));
      final result = await g.summary({'period': 'monthly', 'year': '2026', 'month': '11', 'compare': 'true'});
      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/v1/reports/summary');
      expect(seen.url.queryParameters, {'period': 'monthly', 'year': '2026', 'month': '11', 'compare': 'true'});
      expect(seen.headers['Authorization'], 'Bearer t1');
      expect((result['training'] as Map)['sessions'], 2);
    });

    test('a path prefix on the base address is kept', () async {
      late Uri seen;
      final g = HttpReportingGateway(
        baseUrl: Uri.parse('https://example.com/reporting'),
        token: ({bool force = false}) async => 't',
        client: MockClient((r) async {
          seen = r.url;
          return json(summaryJson());
        }),
      );
      await g.summary({'period': 'complete'});
      expect(seen.path, '/reporting/api/v1/reports/summary');
    });

    test('after a 401 it refreshes the token and tries once more', () async {
      final tokens = <String>[];
      final forced = <bool>[];
      final g = gateway(MockClient((r) async {
        tokens.add(r.headers['Authorization']!);
        return tokens.length == 1 ? json({'detail': 'Invalid token'}, 401) : json(summaryJson());
      }), forced: forced);
      await g.summary({'period': 'complete'});
      expect(tokens, ['Bearer t1', 'Bearer t2']);
      expect(forced, [false, true]);
    });

    test('two 401s in a row is an unauthorized error, with no endless retry', () async {
      var calls = 0;
      final g = gateway(MockClient((r) async {
        calls++;
        return json({'detail': 'Invalid token'}, 401);
      }));
      await expectLater(g.summary({'period': 'complete'}), throwsA(isA<ReportError>().having((e) => e.kind, 'kind', ReportErrorKind.unauthorized)));
      expect(calls, 2);
    });

    test('no token means signed out, and no request is made', () async {
      var calls = 0;
      final g = gateway(MockClient((r) async {
        calls++;
        return json(summaryJson());
      }), tokenOverride: () => null);
      await expectLater(g.summary({'period': 'complete'}), throwsA(isA<ReportError>().having((e) => e.kind, 'kind', ReportErrorKind.unauthorized)));
      expect(calls, 0);
    });

    final cases = <int, ReportErrorKind>{
      403: ReportErrorKind.notOwner,
      413: ReportErrorKind.tooLarge,
      422: ReportErrorKind.invalidRequest,
      503: ReportErrorKind.serviceUnavailable,
      500: ReportErrorKind.server,
    };
    cases.forEach((status, kind) {
      test('HTTP $status becomes $kind', () async {
        final g = gateway(MockClient((r) async => json({'detail': 'Because reasons'}, status)));
        await expectLater(
          g.summary({'period': 'complete'}),
          throwsA(isA<ReportError>().having((e) => e.kind, 'kind', kind).having((e) => e.statusCode, 'status', status)),
        );
      });
    });

    test('a FastAPI validation list is turned into readable text', () async {
      final g = gateway(MockClient((r) async => json({
            'detail': [
              {'loc': ['query', 'month'], 'msg': 'Input should be less than or equal to 12'},
            ],
          }, 422)));
      try {
        await g.summary({'period': 'monthly'});
        fail('should throw');
      } on ReportError catch (e) {
        expect(e.message, contains('Input should be less than or equal to 12'));
        expect(e.kind, ReportErrorKind.invalidRequest);
      }
    });

    test('a connection failure is unreachable and counts as offline', () async {
      final g = gateway(MockClient((r) async => throw http.ClientException('no route')));
      try {
        await g.summary({'period': 'complete'});
        fail('should throw');
      } on ReportError catch (e) {
        expect(e.kind, ReportErrorKind.unreachable);
        expect(e.isOffline, isTrue);
      }
    });

    test('a socket failure is unreachable', () async {
      final g = gateway(MockClient((r) async => throw const SocketException('down')));
      await expectLater(g.summary({'period': 'complete'}), throwsA(isA<ReportError>().having((e) => e.kind, 'kind', ReportErrorKind.unreachable)));
    });

    test('a slow service is a timeout', () async {
      final g = HttpReportingGateway(
        baseUrl: base,
        summaryTimeout: const Duration(milliseconds: 30),
        token: ({bool force = false}) async => 't',
        client: MockClient((r) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return json(summaryJson());
        }),
      );
      await expectLater(g.summary({'period': 'complete'}), throwsA(isA<ReportError>().having((e) => e.kind, 'kind', ReportErrorKind.timeout)));
    });

    test('an answer that is not JSON is a bad response', () async {
      final g = gateway(MockClient((r) async => http.Response('<html>proxy error</html>', 200)));
      await expectLater(g.summary({'period': 'complete'}), throwsA(isA<ReportError>().having((e) => e.kind, 'kind', ReportErrorKind.badResponse)));
    });
  });

  group('downloads', () {
    test('a report is saved under the server file name and sent the format', () async {
      late Uri seen;
      final g = gateway(MockClient((r) async {
        seen = r.url;
        return http.Response.bytes([1, 2, 3, 4, 5], 200, headers: {'content-disposition': 'attachment; filename="fitness-report-2026-11.xlsx"'});
      }));
      final progress = <int>[];
      final file = await g.downloadReport(query: {'period': 'monthly', 'year': '2026', 'month': '11'}, format: ReportFormat.xlsx, directory: dir.path, onProgress: (got, total) => progress.add(got));
      expect(seen.path, '/api/v1/reports/export');
      expect(seen.queryParameters['format'], 'xlsx');
      expect(seen.queryParameters['period'], 'monthly');
      expect(file.fileName, 'fitness-report-2026-11.xlsx');
      expect(file.sizeBytes, 5);
      expect(File(file.path).readAsBytesSync(), [1, 2, 3, 4, 5]);
      expect(progress.last, 5);
      expect(dir.listSync().whereType<File>().where((f) => f.path.endsWith('.part')), isEmpty);
    });

    test('an earlier file with the same name is never overwritten', () async {
      final g = gateway(MockClient((r) async => http.Response.bytes([9], 200, headers: {'content-disposition': 'attachment; filename="r.pdf"'})));
      final a = await g.downloadReport(query: {'period': 'complete'}, format: ReportFormat.pdf, directory: dir.path);
      final b = await g.downloadReport(query: {'period': 'complete'}, format: ReportFormat.pdf, directory: dir.path);
      expect(a.fileName, 'r.pdf');
      expect(b.fileName, 'r-1.pdf');
    });

    test('a hostile file name cannot leave the export folder', () async {
      final g = gateway(MockClient((r) async => http.Response.bytes([9], 200, headers: {'content-disposition': 'attachment; filename="../../evil.pdf"'})));
      final f = await g.downloadReport(query: {'period': 'complete'}, format: ReportFormat.pdf, directory: dir.path);
      expect(File(f.path).parent.path, dir.path);
      expect(f.fileName, isNot(contains('/')));
    });

    test('an error answer saves nothing and reports the detail', () async {
      final g = gateway(MockClient((r) async => json({'detail': 'Report generation failed'}, 503)));
      await expectLater(g.downloadReport(query: {'period': 'complete'}, format: ReportFormat.pdf, directory: dir.path), throwsA(isA<ReportError>().having((e) => e.kind, 'kind', ReportErrorKind.serviceUnavailable)));
      expect(dir.listSync(), isEmpty);
    });

    test('an empty file is an error, not a saved file', () async {
      final g = gateway(MockClient((r) async => http.Response.bytes([], 200)));
      await expectLater(g.downloadReport(query: {'period': 'complete'}, format: ReportFormat.pdf, directory: dir.path), throwsA(isA<ReportError>().having((e) => e.kind, 'kind', ReportErrorKind.badResponse)));
      expect(dir.listSync(), isEmpty);
    });

    test('full backup sends no format; media only when asked', () async {
      final urls = <Uri>[];
      final g = gateway(MockClient((r) async {
        urls.add(r.url);
        return http.Response.bytes([1], 200);
      }));
      final full = await g.downloadBackup(kind: BackupKind.fullZip, directory: dir.path);
      await g.downloadBackup(kind: BackupKind.fullZip, includeMedia: true, directory: dir.path);
      expect(urls[0].path, '/api/v1/backup/export');
      expect(urls[0].queryParameters, isEmpty);
      expect(urls[1].queryParameters, {'include_media': 'true'});
      expect(full.fileName, 'fitness-backup.zip');
    });

    test('CSV export asks for format=csv and ignores include_media', () async {
      late Uri seen;
      final g = gateway(MockClient((r) async {
        seen = r.url;
        return http.Response.bytes([1], 200);
      }));
      final f = await g.downloadBackup(kind: BackupKind.csvZip, includeMedia: true, directory: dir.path);
      expect(seen.queryParameters, {'format': 'csv'});
      expect(f.fileName, 'fitness-export.zip');
    });
  });

  group('validateBackup', () {
    test('posts the file as multipart field "file" and parses the answer', () async {
      final backup = File('${dir.path}/b.zip')..writeAsBytesSync([80, 75, 3, 4]);
      late http.BaseRequest seen;
      late String body;
      final g = gateway(MockClient((r) async {
        seen = r;
        body = latin1.decode(r.bodyBytes);
        return json({
          'ok': false,
          'errors': ['missing table x'],
          'warnings': ['media not included'],
          'counts': {'workout_session': 3, 'exercise': 7},
          'exported_at': '2026-11-14T10:00:00+00:00',
          'format_version': 1,
          'media_included': false,
        });
      }));
      final v = await g.validateBackup(backup.path);
      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/v1/backup/validate');
      expect(seen.headers['Authorization'], 'Bearer t1');
      expect(seen.headers['content-type'], startsWith('multipart/form-data'));
      expect(body, contains('name="file"'));
      expect(v.ok, isFalse);
      expect(v.errors, ['missing table x']);
      expect(v.warnings, ['media not included']);
      expect(v.totalRows, 10);
      expect(v.formatVersion, 1);
      expect(v.mediaIncluded, isFalse);
      expect(v.exportedAt, DateTime.utc(2026, 11, 14, 10));
    });

    test('a too-large file is reported as such', () async {
      final backup = File('${dir.path}/b.zip')..writeAsBytesSync([1]);
      final g = gateway(MockClient((r) async => json({'detail': 'File too large'}, 413)));
      await expectLater(g.validateBackup(backup.path), throwsA(isA<ReportError>().having((e) => e.kind, 'kind', ReportErrorKind.tooLarge)));
    });

    test('a file that is gone is a file problem, with no request', () async {
      var calls = 0;
      final g = gateway(MockClient((r) async {
        calls++;
        return json({});
      }));
      await expectLater(g.validateBackup('${dir.path}/missing.zip'), throwsA(isA<ReportError>().having((e) => e.kind, 'kind', ReportErrorKind.fileProblem)));
      expect(calls, 0);
    });
  });

  test('NotConfiguredReportingGateway refuses every call with a clear message', () async {
    final g = NotConfiguredReportingGateway('REPORT_API_URL is not set.');
    await expectLater(g.summary({}), throwsA(isA<ReportError>().having((e) => e.kind, 'kind', ReportErrorKind.notConfigured)));
    await expectLater(g.validateBackup('x'), throwsA(isA<ReportError>().having((e) => e.kind, 'kind', ReportErrorKind.notConfigured)));
  });
}
