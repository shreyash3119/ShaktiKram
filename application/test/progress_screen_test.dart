import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/backend/backend_error.dart';
import 'package:shaktikram/core/routing/app_shell.dart';

import 'support/fakes.dart';
import 'support/store_contract.dart';

Future<void> _open(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const Key('nav-Progress')),
  );
  await tester.pumpAndSettle();
}

Future<void> _pill(WidgetTester tester, String label) async {
  final tab = find.byKey(Key('tab-$label'));
  await tester.ensureVisible(tab);
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty phone shows empty states, not sample numbers', (
    tester,
  ) async {
    final h = Harness.ready();

    await _open(tester, h);

    // Overview: four tiles and two cards, all empty.
    expect(find.text('None yet'), findsOneWidget);
    expect(find.text('Log two sessions of an exercise to see a trend.'), findsOneWidget);
    expect(find.text('No counted working sets yet.'), findsOneWidget);
    expect(find.text('Calculated by the server. Not medical advice.'), findsOneWidget);

    await _pill(tester, 'Strength');
    expect(find.text('No data'), findsNWidgets(2));
    expect(find.text('No records'), findsOneWidget);
    expect(find.text('Nothing to show yet'), findsOneWidget);
    expect(find.text('Estimates are from your records, not direct measurements.'), findsOneWidget);

    await _pill(tester, 'Goals');
    expect(find.text('No goals yet. Create one to track it here.'), findsOneWidget);
    expect(find.text('New goal'), findsOneWidget);
    expect(find.text('Archived goals (0)'), findsOneWidget);
    expect(find.text('None yet. Open a goal to add one.'), findsOneWidget);
  });

  testWidgets('Body and Muscles show their empty states and actions', (tester) async {
    final h = Harness.ready();
    await _open(tester, h);

    await _pill(tester, 'Body');
    expect(find.text('Log your weight on at least two days to see a line.'), findsOneWidget);
    expect(find.text('Log weight'), findsOneWidget);
    expect(find.text('Add in Lifestyle'), findsOneWidget);

    await _pill(tester, 'Muscles');
    expect(find.text('Your ratings'), findsOneWidget);
    expect(find.text('Rate your muscles'), findsOneWidget);
    expect(find.text('No counted sets yet.'), findsOneWidget);
    expect(find.text('Darker bar = more direct sets.'), findsOneWidget);
    expect(find.text('Muscles with little direct work'), findsOneWidget);
  });

  testWidgets('a logged weight shows on the Overview tile and the Body tab', (tester) async {
    final h = Harness.ready();
    await h.local.applyPulled([
      pulled('body_measurements', 1, {
        'id': uid(1),
        'occurred_at': '2026-11-10T07:00:00Z',
        'local_date': '2026-11-10',
        'tz_offset_minutes': 0,
        'measurement_type': 'weight',
        'value': 78,
        'source': 'manual',
      }),
    ], 1);
    await _open(tester, h);
    expect(find.descendant(of: find.byKey(const Key('tile-weight')), matching: find.text('78 kg')), findsOneWidget);

    await _pill(tester, 'Body');
    expect(find.byKey(const Key('body-weight-value')), findsOneWidget);
    expect(find.text('Body weight · Nov 10'), findsOneWidget);
    expect(find.byKey(const Key('body-weight-row')), findsOneWidget);
  });

  testWidgets(
    'records and goals on the phone are shown, goal progress comes from the server',
    (tester) async {
      final h = Harness.ready();
      await h.local.applyPulled([
        pulled('personal_records', 1, {
          'id': uid(1),
          'kind': 'max_weight',
          'value': 85,
          'achieved_on': '2026-11-10',
          'session_id': uid(50),
          'exercise_id': uid(60),
        }),
        pulled('goals', 2, {
          'id': uid(2),
          'type': 'strength',
          'title': 'Bench 90 kg',
          'status': 'active',
          'start_date': '2026-10-01',
          'target_value': 90,
        }),
        pulled('goals', 3, {
          'id': uid(3),
          'type': 'body',
          'title': 'Lean bulk',
          'status': 'abandoned',
          'start_date': '2026-01-01',
          'target_value': 80,
          'target_unit': 'kg',
        }),
      ], 3);
      h.gateway.viewRows['v_goal_progress'] = [
        {
          'goal_id': uid(2),
          'title': 'Bench 90 kg',
          'goal_status': 'active',
          'progress_status': 'on_track',
          'progress_pct': 80,
          'reached': false,
          'current_value': 85,
          'target_value': 90,
        },
      ];
      await _open(tester, h);
      expect(find.descendant(of: find.byKey(const Key('tile-record')), matching: find.text('85 kg')), findsOneWidget);

      await _pill(tester, 'Strength');
      expect(find.text('1 record'), findsOneWidget);
      expect(find.textContaining('Heaviest weight'), findsWidgets);

      await _pill(tester, 'Goals');
      expect(find.text('Bench 90 kg'), findsWidgets);
      expect(find.text('Active'), findsOneWidget);
      expect(find.textContaining('On track (80%)'), findsOneWidget);
      expect(find.text('Archived goals (1)'), findsOneWidget);
      expect(find.textContaining('Lean bulk (archived) · target 80 kg'), findsOneWidget);
    },
  );

  testWidgets(
    'when the server cannot be reached the saved answer stays and is labelled offline',
    (tester) async {
      final h = Harness.ready();
      await h.local.applyPulled([
        pulled('goals', 1, {
          'id': uid(2),
          'type': 'strength',
          'title': 'Bench 90 kg',
          'status': 'active',
          'start_date': '2026-10-01',
        }),
      ], 1);
      await h.local.writeInsight(
        'view:v_goal_progress',
        '[{"goal_id":"${uid(2)}","title":"Bench 90 kg","goal_status":"active","progress_status":"behind","progress_pct":40}]',
        DateTime.now().subtract(const Duration(hours: 5)),
      );
      h.gateway.insightError = const BackendError.unreachable();
      await _open(tester, h);
      await _pill(tester, 'Goals');
      expect(find.textContaining('Behind (40%)'), findsOneWidget);
      expect(find.byKey(const Key('insight-status')), findsWidgets);
    },
  );

  testWidgets('the info button explains where the numbers come from', (tester) async {
    await _open(tester, Harness.ready());
    await tester.tap(find.byKey(const Key('progress-info')));
    await tester.pumpAndSettle();
    expect(find.text('About these numbers'), findsOneWidget);
    expect(find.byKey(const Key('progress-refresh')), findsOneWidget);
  });
}
