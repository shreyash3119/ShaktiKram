import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/routing/app_shell.dart';
import 'package:shaktikram/core/sync/change_writer.dart';
import 'package:shaktikram/features/training/data/training_providers.dart';

import 'support/fakes.dart';

/// Opens the app on a phone that already holds one exercise, then taps Start workout on Home.
Future<(Harness, ProviderContainer)> _openSession(WidgetTester tester) async {
  final h = Harness.ready();
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ShaktiKramApp)),
  );
  await container.read(changeWriterProvider).upsert('exercises', {
    'name': 'Bench press',
    'category': 'compound',
    'is_custom': true,
  });
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start workout'));
  await tester.pumpAndSettle();
  return (h, container);
}

/// Scrolls [target] into view, waits for the scroll to be laid out, then taps it. Without the wait the tap lands where the
/// widget was before the scroll.
Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// The session screen has a running clock, so end each test by removing the screen.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets(
    'with no workout running the screen offers to start one, without the bottom bar',
    (tester) async {
      await _openSession(tester);

      expect(find.text('Start empty workout'), findsOneWidget);
      expect(find.byType(AppBottomBar), findsNothing);
      await _close(tester);
    },
  );

  testWidgets(
    'an empty workout takes an exercise and a confirmed set is saved on the phone',
    (tester) async {
      final (h, _) = await _openSession(tester);

      await tester.tap(find.text('Start empty workout'));
      await tester.pumpAndSettle();
      expect(
        (await h.local.list('workout_sessions')).single['status'],
        'in_progress',
      );

      await tester.tap(find.text('Add ›').first);
      await tester.pumpAndSettle();
      expect(find.text('Bench press'), findsWidgets);

      final confirm = find.byKey(const Key('confirm-set'));
      await _tapVisible(tester, confirm);
      await tester.pump();
      expect(find.text('Enter weight and reps first.'), findsOneWidget);
      // Let the message go away: it sits over the bottom of the screen and would catch the next tap.
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('Enter weight and reps first.'), findsNothing);

      await tester.enterText(find.byKey(const Key('kg-field')), '60');
      await tester.enterText(find.byKey(const Key('reps-field')), '8');
      await _tapVisible(tester, confirm);
      await tester.pumpAndSettle();

      final sets = await h.local.list('sets');
      expect(sets.single['weight_kg'], 60);
      expect(sets.single['reps'], 8);
      expect(sets.single['set_number'], 1);
      expect(find.text('Working set 1'), findsOneWidget);
      expect(find.text('Rest'), findsOneWidget);
      await _close(tester);
    },
  );

  testWidgets('leaving asks first and Keep going stays', (tester) async {
    await _openSession(tester);
    await tester.tap(find.text('Start empty workout'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('session-back')));
    await tester.pumpAndSettle();
    expect(find.text('Leave workout?'), findsOneWidget);

    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    expect(find.text('Leave workout?'), findsNothing);
    expect(find.text('Pause or finish'), findsOneWidget);
    await _close(tester);
  });

  testWidgets(
    'finishing a workout with a logged set completes it and shows the summary',
    (tester) async {
      final (h, _) = await _openSession(tester);
      await tester.tap(find.text('Start empty workout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ›').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('kg-field')), '60');
      await tester.enterText(find.byKey(const Key('reps-field')), '8');
      await _tapVisible(tester, find.byKey(const Key('confirm-set')));

      // Wait until the logged set is reflected in the workout screen.
      await tester.pumpAndSettle();
      expect(find.text('Working set 1'), findsOneWidget);

      final finishButton = find.text('Finish workout');
      await _tapVisible(tester, finishButton);
      expect(find.text('Confirm: finish workout?'), findsOneWidget);
      expect(find.text('Confirm: finish workout?'), findsOneWidget);
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();

      expect(find.text('Workout complete'), findsOneWidget);
      expect(
        (await h.local.list('workout_sessions')).single['status'],
        'completed',
      );
      await _close(tester);
    },
  );

  testWidgets(
    'finishing a workout with no sets offers Return or Discard and never completes it',
    (tester) async {
      final (h, _) = await _openSession(tester);
      await tester.tap(find.text('Start empty workout'));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('Finish workout'));
      expect(find.text('No sets logged'), findsOneWidget);
      expect(find.text('Finish'), findsNothing);

      await tester.tap(find.text('Return to workout'));
      await tester.pumpAndSettle();
      expect(
        (await h.local.list('workout_sessions')).single['status'],
        'in_progress',
      );

      await _tapVisible(tester, find.text('Finish workout'));
      await tester.tap(find.text('Discard workout'));
      await tester.pumpAndSettle();
      expect(await h.local.list('workout_sessions'), isEmpty);
      await _close(tester);
    },
  );

  testWidgets(
    'leaving while paused ends the pause and records the time paused',
    (tester) async {
      final (h, _) = await _openSession(tester);
      await tester.tap(find.text('Start empty workout'));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('Pause workout'));
      expect(
        (await h.local.list('workout_sessions')).single['status'],
        'paused',
      );
      expect(find.textContaining('paused'), findsWidgets);

      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const Key('session-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & exit'));
      await tester.pumpAndSettle();

      final session = (await h.local.list('workout_sessions')).single;
      expect(session['status'], 'in_progress');
      expect(session['paused_seconds'], greaterThanOrEqualTo(0));
      await _close(tester);
    },
  );

  testWidgets(
    'a workout saved as paused by an earlier run is not shown as paused with a running clock',
    (tester) async {
      final (h, container) = await _openSession(tester);
      final service = container.read(workoutSessionServiceProvider);
      final id = await service.startSession();
      await service.setPaused(id, paused: true);
      expect(
        (await h.local.list('workout_sessions')).single['status'],
        'paused',
      );
      await tester.pumpAndSettle();

      // Opening the screen on it ends the pause instead of guessing how long it lasted.
      await tester.pumpAndSettle();
      expect(
        (await h.local.list('workout_sessions')).single['status'],
        'in_progress',
      );
      expect(find.text('Pause workout'), findsOneWidget);
      await _close(tester);
    },
  );
}
