import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/config/app_config.dart';
import 'package:shaktikram/features/reports/data/report_models.dart';
import 'package:shaktikram/features/reports/data/report_period.dart';

import 'support/report_fixtures.dart';

void main() {
  group('ReportSummary.fromJson', () {
    test('reads every section of a real-shaped summary', () {
      final s = ReportSummary.fromJson(summaryJson(compare: true));
      expect(s.period.label, 'November 2026');
      expect(s.period.days, 30);
      expect(s.training.sessions, 2);
      expect(s.training.volumeKg, 12450);
      expect(s.training.weekly, hasLength(2));
      expect(s.training.attendance.consistencyPct, 85.7);
      expect(s.training.attendance.weekly.single.missed, 1);
      expect(s.strength.exercises.single.e1rmChangePct, 5.0);
      expect(s.strength.e1rmSeries['Bench press'], hasLength(2));
      expect(s.strength.records.single.kind, 'max_weight');
      expect(s.strength.valueKind, 'estimated');
      expect(s.body.measurements.single.count, 2);
      expect(s.body.weightSeries.last.value, 79.6);
      expect(s.body.composition.single.bodyFatPct, 18.5);
      expect(s.muscles.valueKind, 'user_assessment');
      expect(s.muscles.ratings.single.change, 'higher_rating');
      expect(s.muscles.exposure.single.directSets, 12);
      expect(s.injuries.injuries.single.suggestProfessionalReview, isTrue);
      expect(s.injuries.painEntries, 3);
      expect(s.recovery.sleepAvgHours, 7.2);
      expect(s.recovery.checkinDays, 10);
      expect(s.lifestyle.avgSteps, 8200);
      expect(s.lifestyle.supplements.single.adherencePct, 87.0);
      expect(s.goals.goals.single.progressStatus, 'on_track');
      expect(s.goals.milestones.single.isReached, isTrue);
      expect(s.context.splits.single.name, 'Push Pull Legs');
      expect(s.context.breaks.single.daysInPeriod, 2);
      expect(s.context.deloads.single.status, 'planned');
      expect(s.observations.map((o) => o.code), [
        'training_volume',
        'consistency',
      ]);
      expect(s.comparison!.previousPeriod.label, 'October 2026');
      expect(s.comparison!.metrics.first.changePct, -50);
      expect(s.comparison!.metrics.last.previous, isNull);
    });

    test('has no comparison unless the service sent one', () {
      expect(ReportSummary.fromJson(summaryJson()).comparison, isNull);
    });

    test('an empty period parses to zeros and empty lists, not errors', () {
      final json = {
        'period': {
          'kind': 'daily',
          'label': '2026-11-14',
          'start': '2026-11-14',
          'end': '2026-11-14',
          'days': 1,
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
      final s = ReportSummary.fromJson(json);
      expect(s.training.sessions, 0);
      expect(s.strength.exercises, isEmpty);
      expect(s.body.measurements, isEmpty);
      expect(s.goals.goals, isEmpty);
      expect(s.observations, isEmpty);
    });

    test('numbers may arrive as ints, doubles or null', () {
      final json = Map<String, dynamic>.from(summaryJson());
      final training = Map<String, dynamic>.from(json['training'] as Map);

      training['volume_kg'] = 1000;
      training['avg_duration_min'] = null;
      json['training'] = training;

      final s = ReportSummary.fromJson(json);
      expect(s.training.volumeKg, 1000.0);
      expect(s.training.avgDurationMin, isNull);
    });

    test('a summary without period or training is rejected', () {
      expect(
        () => ReportSummary.fromJson({'training': {}}),
        throwsFormatException,
      );
      expect(
        () => ReportSummary.fromJson({
          'period': {'kind': 'monthly', 'label': 'x'},
        }),
        throwsFormatException,
      );
    });
  });

  group('ReportQuery', () {
    test('monthly parameters, label and cache key', () {
      final q = ReportQuery.monthly(2026, 11);
      expect(q.toParams(), {
        'period': 'monthly',
        'year': '2026',
        'month': '11',
      });
      expect(q.toParams(compare: true)['compare'], 'true');
      expect(q.label, 'November 2026');
      expect(
        ReportRequest(q).cacheKey,
        isNot(ReportRequest(q, compare: true).cacheKey),
      );
      expect(ReportRequest(q), ReportRequest(ReportQuery.monthly(2026, 11)));
    });

    test('each kind sends the parameters the service names', () {
      expect(ReportQuery.daily(DateTime(2026, 11, 14)).toParams(), {
        'period': 'daily',
        'day': '2026-11-14',
      });
      expect(ReportQuery.weekly(DateTime(2026, 11, 14)).toParams(), {
        'period': 'weekly',
        'week_start': '2026-11-09',
      });
      expect(ReportQuery.quarterly(2026, 4).toParams(), {
        'period': 'quarterly',
        'year': '2026',
        'quarter': '4',
      });
      expect(ReportQuery.halfYearly(2026, 2).toParams(), {
        'period': 'half_yearly',
        'year': '2026',
        'half': '2',
      });
      expect(ReportQuery.yearly(2026).toParams(), {
        'period': 'yearly',
        'year': '2026',
      });
      expect(
        ReportQuery.custom(
          DateTime(2026, 1, 1),
          DateTime(2026, 1, 31),
        ).toParams(),
        {
          'period': 'custom',
          'date_from': '2026-01-01',
          'date_to': '2026-01-31',
        },
      );
      expect(const ReportQuery.complete().toParams(), {'period': 'complete'});
    });

    test('labels match the service wording', () {
      expect(
        ReportQuery.weekly(DateTime(2026, 11, 14)).label,
        'Week of 2026-11-09',
      );
      expect(ReportQuery.quarterly(2026, 4).label, 'Q4 2026');
      expect(ReportQuery.halfYearly(2026, 2).label, 'H2 2026');
      expect(const ReportQuery.complete().label, 'Complete history');
    });

    test(
      'stepping crosses year boundaries and stops for custom and all time',
      () {
        expect(
          ReportQuery.monthly(2026, 1).shifted(-1),
          ReportQuery.monthly(2025, 12),
        );
        expect(
          ReportQuery.monthly(2026, 12).shifted(1),
          ReportQuery.monthly(2027, 1),
        );
        expect(
          ReportQuery.quarterly(2026, 1).shifted(-1),
          ReportQuery.quarterly(2025, 4),
        );
        expect(
          ReportQuery.halfYearly(2026, 2).shifted(1),
          ReportQuery.halfYearly(2027, 1),
        );
        expect(
          ReportQuery.weekly(DateTime(2026, 11, 9)).shifted(-1),
          ReportQuery.weekly(DateTime(2026, 11, 2)),
        );
        expect(
          ReportQuery.custom(
            DateTime(2026, 1, 1),
            DateTime(2026, 1, 31),
          ).canStep,
          isFalse,
        );
        expect(const ReportQuery.complete().canStep, isFalse);
      },
    );

    test('knows when a period has not started', () {
      final today = DateTime(2026, 11, 14);
      expect(ReportQuery.monthly(2026, 11).startsAfter(today), isFalse);
      expect(ReportQuery.monthly(2026, 12).startsAfter(today), isTrue);
      expect(const ReportQuery.complete().startsAfter(today), isFalse);
    });

    test('validation', () {
      expect(ReportQuery.monthly(2026, 11).validate(), isNull);
      expect(ReportQuery.monthly(1800, 1).validate(), isNotNull);
      expect(
        ReportQuery.custom(
          DateTime(2026, 2, 1),
          DateTime(2026, 1, 1),
        ).validate(),
        contains('before'),
      );
      expect(
        ReportQuery.custom(
          DateTime(2010, 1, 1),
          DateTime(2026, 1, 1),
        ).validate(),
        contains('$maxCustomDays'),
      );
      expect(
        ReportQuery.custom(
          DateTime(2026, 1, 1),
          DateTime(2026, 1, 1),
        ).validate(),
        isNull,
      );
      expect(const ReportQuery.complete().validate(), isNull);
    });
  });

  group('AppConfig.checkReportUrl', () {
    test('accepts https and strips a trailing slash', () {
      final r = AppConfig.checkReportUrl('https://reports.example.com/');
      expect(r.baseUrl.toString(), 'https://reports.example.com');
    });
    test('accepts http only for a computer on the local network', () {
      expect(
        AppConfig.checkReportUrl('http://10.0.2.2:8000').baseUrl,
        isNotNull,
      );
      expect(
        AppConfig.checkReportUrl('http://192.168.1.20:8000').baseUrl,
        isNotNull,
      );
      expect(
        AppConfig.checkReportUrl('http://localhost:8000').baseUrl,
        isNotNull,
      );
      expect(
        AppConfig.checkReportUrl('http://reports.example.com').problem,
        contains('https'),
      );
    });
    test('rejects empty and malformed addresses', () {
      expect(AppConfig.checkReportUrl('').problem, contains('not set'));
      expect(AppConfig.checkReportUrl('not a url').problem, isNotNull);
      expect(
        AppConfig.checkReportUrl('ftp://x.example.com').problem,
        isNotNull,
      );
      expect(
        AppConfig.checkReportUrl('https://x.example.com/?a=1').problem,
        isNotNull,
      );
    });
  });
}
