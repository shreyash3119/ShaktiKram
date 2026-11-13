import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/routing/app_shell.dart';
import 'package:shaktikram/core/time/local_stamp.dart';
import 'package:shaktikram/core/widgets/controls.dart';

import 'support/fakes.dart';
import 'support/store_contract.dart';

Future<void> _open(WidgetTester tester, Harness h, String tab) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(AppBottomBar), matching: find.text(tab)));
  await tester.pumpAndSettle();
}

Future<void> _pill(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(PillTabs).first, matching: find.text(label)));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _seedMuscles(Harness h) => h.local.applyPulled([
      pulled('muscles', 1, {'id': uid(1), 'key': 'chest', 'label': 'Chest', 'group_key': 'chest'}),
      pulled('muscles', 2, {'id': uid(2), 'key': 'triceps', 'label': 'Triceps', 'group_key': 'arms'}),
    ], 2);

void main() {
  testWidgets('an exercise can be added from the Exercises tab', (tester) async {
    final h = Harness.ready();
    await _seedMuscles(h);
    await _open(tester, h, 'Training');
    await _pill(tester, 'Exercises');

    await _tapVisible(tester, find.text('Add an exercise'));
    await tester.enterText(find.byKey(const Key('exercise-name')), 'Incline press');
    await _tapVisible(tester, find.descendant(of: find.byType(BottomSheet), matching: find.text('Chest')).first);
    await _tapVisible(tester, find.text('Save exercise'));

    expect((await h.local.list('exercises')).single['name'], 'Incline press');
    expect((await h.local.list('exercise_muscles')).single['role'], 'primary');
    expect(find.text('Incline press'), findsOneWidget);
  });

  testWidgets('saving an exercise without a muscle shows the reason and saves nothing', (tester) async {
    final h = Harness.ready();
    await _seedMuscles(h);
    await _open(tester, h, 'Training');
    await _pill(tester, 'Exercises');

    await _tapVisible(tester, find.text('Add an exercise'));
    await tester.enterText(find.byKey(const Key('exercise-name')), 'Incline press');
    await _tapVisible(tester, find.text('Save exercise'));

    expect(find.text('Choose at least one main muscle.'), findsOneWidget);
    expect(await h.local.list('exercises'), isEmpty);
  });

  testWidgets('a split can be created and made active from the Splits tab', (tester) async {
    final h = Harness.ready();
    await _open(tester, h, 'Training');
    await _pill(tester, 'Splits');

    await _tapVisible(tester, find.text('Create a split'));
    await tester.enterText(find.byKey(const Key('split-name')), 'PPL');
    await _tapVisible(tester, find.text('Add day'));
    await tester.enterText(find.byKey(const Key('day-name-0')), 'Push');
    await _tapVisible(tester, find.text('Save split'));

    expect((await h.local.list('splits')).single['status'], 'draft');
    expect(find.text('PPL'), findsOneWidget);
    expect(find.text('Not active'), findsOneWidget);
  });

  testWidgets('History lists a workout with no sets as not counted and offers to discard it', (tester) async {
    final h = Harness.ready();
    final today = localStampOf(DateTime.now()).localDate;
    await h.local.applyPulled([
      pulled('workout_sessions', 1, {
        'id': uid(7),
        'occurred_at': DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String(),
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'local_date': today,
        'status': 'completed',
        'name': 'Test session',
      }),
    ], 1);
    await _open(tester, h, 'Training');
    await _pill(tester, 'History');

    expect(find.textContaining('No sets logged, not counted'), findsOneWidget);
    await tester.tap(find.text('Test session'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not counted in your totals'), findsWidgets);

    await _tapVisible(tester, find.text('Discard this workout'));
    await tester.tap(find.text('Discard').last);
    await tester.pumpAndSettle();
    expect(await h.local.list('workout_sessions'), isEmpty);
  });

  testWidgets('Progress > Goals: a goal can be created, and a completed one shows no progress bar', (tester) async {
    final h = Harness.ready();
    await h.local.applyPulled([
      pulled('goals', 1, {'id': uid(5), 'type': 'bulking', 'title': 'Lean bulk', 'status': 'completed', 'start_date': '2026-09-01', 'target_value': 80, 'target_unit': 'kg'}),
    ], 1);
    await _open(tester, h, 'Progress');
    await _pill(tester, 'Goals');

    expect(find.text('Lean bulk'), findsOneWidget);
    expect(find.textContaining('Completed · target 80 kg'), findsOneWidget);

    await _tapVisible(tester, find.text('New goal'));
    await tester.enterText(find.byKey(const Key('goal-title')), 'Bench 100 kg');
    await _tapVisible(tester, find.descendant(of: find.byType(BottomSheet), matching: find.text('Strength')).first);
    await _tapVisible(tester, find.text('Save goal'));

    final titles = [for (final g in await h.local.list('goals')) g['title']];
    expect(titles, containsAll(['Lean bulk', 'Bench 100 kg']));
  });

  testWidgets('Progress > Muscles: ratings are saved as an assessment', (tester) async {
    final h = Harness.ready();
    await _seedMuscles(h);
    await _open(tester, h, 'Progress');
    await _pill(tester, 'Muscles');

    await _tapVisible(tester, find.text('Rate your muscles'));
    await _tapVisible(tester, find.byKey(const Key('rate-chest-2')));
    await _tapVisible(tester, find.text('Save assessment'));

    expect((await h.local.list('muscle_assessments')).length, 1);
    expect((await h.local.list('muscle_assessment_items')).single['level'], 2);
  });
}
