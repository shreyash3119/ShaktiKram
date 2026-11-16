import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/time/local_stamp.dart';
import 'support/store_contract.dart';
import 'support/fakes.dart';

Future<void> _open(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()),
  );
  await tester.pumpAndSettle();
}

Future<void> _setStatus(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(const Key('home-status-pill')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('status-$id')));
  await tester.pumpAndSettle();
}

String _today() => localStampOf(DateTime.now()).localDate;

void main() {
  testWidgets('with nothing set, the pill says Set status and the card offers to start', (tester) async {
    await _open(tester, Harness.ready());
    expect(find.text('Set status'), findsOneWidget);
    expect(find.text('No workout planned'), findsOneWidget);
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('Open Training ›'), findsOneWidget);
  });

  testWidgets('the status dialog lists the four states and the completed note', (tester) async {
    await _open(tester, Harness.ready());
    await tester.tap(find.byKey(const Key('home-status-pill')));
    await tester.pumpAndSettle();
    expect(find.text('Today’s status'), findsOneWidget);
    for (final t in ['Rest', 'Skipped', 'In progress', 'Completed']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Completed without logged sets won’t count in totals or streaks.'), findsOneWidget);
  });

  testWidgets('Rest plans a rest day and the card says planned rest days do not count as missed', (tester) async {
    final h = Harness.ready();
    await _open(tester, h);
    await _setStatus(tester, 'rest');

    final rows = await h.local.list('schedule_entries');
    expect(rows.single['local_date'], _today());
    expect(rows.single['is_rest_day'], true);
    expect(find.text('Rest day'), findsOneWidget);
    expect(find.text('Planned rest days don’t count as missed.'), findsOneWidget);
    expect(find.text('Start a workout anyway'), findsOneWidget);
    expect(find.text('Change status'), findsOneWidget);
  });

  testWidgets('Skipped marks the day, and Plan for tomorrow moves the plan', (tester) async {
    final h = Harness.ready();
    await _open(tester, h);
    await _setStatus(tester, 'skipped');

    expect(find.text('Workout skipped'), findsOneWidget);
    expect((await h.local.list('schedule_entries')).single['status'], 'skipped');

    await tester.tap(find.text('Plan for tomorrow'));
    await tester.pumpAndSettle();
    final rows = await h.local.list('schedule_entries');
    final today = rows.singleWhere((r) => r['local_date'] == _today());
    expect(today['status'], 'rescheduled');
    final tomorrow = today['rescheduled_to'] as String;
    expect(rows.singleWhere((r) => r['local_date'] == tomorrow)['status'], 'planned');
    expect(find.text('Moved to tomorrow.'), findsOneWidget);
  });

  testWidgets('Completed with nothing logged is recorded but says it will not count', (tester) async {
    final h = Harness.ready();
    await _open(tester, h);
    await _setStatus(tester, 'completed');

    expect(find.text('Workout completed'), findsOneWidget);
    expect(find.text('No sets were logged, so it doesn’t count in totals or streaks.'), findsOneWidget);
    final entry = (await h.local.list('schedule_entries')).single;
    expect(entry['status'], 'completed');
    expect(entry['session_id'], isNotNull);
    expect(find.text('View workout'), findsOneWidget);
  });

  testWidgets('a running workout shows as In progress with its name and time, and no Pause button', (tester) async {
    final h = Harness.ready();
    await h.local.applyPulled([
      pulled('workout_sessions', 1, {
        'id': uid(1),
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
        'local_date': _today(),
        'status': 'in_progress',
        'name': 'Push A',
      }),
    ], 1);
    await _open(tester, h);

    expect(find.text('Workout in progress'), findsOneWidget);
    expect(find.textContaining('Push A · 00:'), findsOneWidget);
    expect(find.text('Resume workout'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
  });

  testWidgets('Rest and Skipped are refused while a workout is running', (tester) async {
    final h = Harness.ready();
    await h.local.applyPulled([
      pulled('workout_sessions', 1, {
        'id': uid(1),
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
        'local_date': _today(),
        'status': 'in_progress',
      }),
    ], 1);
    await _open(tester, h);
    await _setStatus(tester, 'rest');

    expect(find.text('Finish or discard the running workout first.'), findsOneWidget);
    expect(await h.local.list('schedule_entries'), isEmpty);
  });

  testWidgets('Add water saves a log for today', (tester) async {
    final h = Harness.ready();
    await _open(tester, h);
    await tester.tap(find.byKey(const Key('quick-add-water')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('water-500')));
    await tester.pumpAndSettle();

    expect((await h.local.list('water_logs')).single['amount_ml'], 500);
    expect(find.text('Added 500 ml of water.'), findsOneWidget);
  });

  testWidgets('the Home screen no longer shows the removed cards', (tester) async {
    await _open(tester, Harness.ready());
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    for (final t in ['Recent activity', 'Highlights', 'Alerts', 'Quick actions', 'Body overview', 'Quick log weight']) {
      expect(find.text(t), findsNothing);
    }
  });
}
