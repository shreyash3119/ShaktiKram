import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/routing/app_shell.dart';
import 'package:shaktikram/core/sync/change_writer.dart';
import 'package:shaktikram/core/widgets/controls.dart';
import 'package:shaktikram/features/training/data/training_management_service.dart';
import 'package:shaktikram/features/training/data/training_providers.dart';
import 'package:shaktikram/features/training/data/workout_session_service.dart';
import 'package:shaktikram/features/training/presentation/training_format.dart';

import 'support/fakes.dart';
import 'support/store_contract.dart';

Future<ProviderContainer> _open(WidgetTester tester, Harness h) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(AppBottomBar), matching: find.text('Training')));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(ShaktiKramApp)));
}

Future<void> _pill(WidgetTester tester, String label) async {
  final target = find.descendant(of: find.byType(PillTabs).first, matching: find.text(label));
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

/// An exercise written straight to the phone (the editor needs a muscle, which these tests do not care about).
Future<String> _exercise(ProviderContainer container) => container.read(changeWriterProvider).upsert('exercises', {'name': 'Bench', 'category': 'compound', 'is_custom': true});

void main() {
  group('format helpers', () {
    test('week range, with and without a month change', () {
      expect(weekRangeText('2026-11-09'), 'Nov 9 – 15');
      expect(weekRangeText('2026-11-30'), 'Nov 30 – Dec 6');
    });

    test('monday and day arithmetic', () {
      expect(mondayOf('2026-11-14'), '2026-11-09');
      expect(mondayOf('2026-11-09'), '2026-11-09');
      expect(mondayOf('2026-11-15'), '2026-11-09');
      expect(datePlus('2026-11-30', 1), '2026-12-01');
      expect(dateText('2026-11-14'), 'Sat, Nov 14');
    });

    test('numbers are grouped in thousands', () {
      expect(kgText(48200), '48,200');
      expect(kgText(6420), '6,420');
      expect(kgText(850.5), '850.5');
      expect(kgText(0), '0');
    });

    test('the streak counts consecutive weeks and forgives a week that has just begun', () {
      // Weeks of Nov 9, Nov 2 and Oct 26 have a workout.
      final dates = ['2026-11-10', '2026-11-03', '2026-10-27'];
      expect(weekStreak(dates, '2026-11-14'), 3);
      // The current week (Nov 16) has none yet: the streak is still the three earlier weeks.
      expect(weekStreak(dates, '2026-11-16'), 3);
      // A missed week in between ends the streak.
      expect(weekStreak(['2026-11-10', '2026-10-27'], '2026-11-14'), 1);
      expect(weekStreak(const [], '2026-11-14'), 0);
      expect(weekStreak(['2026-10-01'], '2026-11-14'), 0);
    });
  });

  testWidgets('Overview with nothing planned offers an empty workout and a way to the Schedule', (tester) async {
    await _open(tester, Harness.ready());
    expect(find.text('No workout planned'), findsOneWidget);
    expect(find.text('Start empty workout'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Nothing planned yet'), findsOneWidget);
    expect(find.text('You are not following a split yet.'), findsOneWidget);
    expect(find.text('New template'), findsOneWidget);
    expect(find.text('Add exercise'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('Finished workouts with logged sets will show up here.'), findsOneWidget);
    expect(find.text('Performance overview'), findsNothing);

    await _tap(tester, find.text('Go to Schedule'));
    expect(find.text('Schedule · this week'), findsOneWidget);
  });

  testWidgets('the week strip shows today and the date of every day', (tester) async {
    await _open(tester, Harness.ready());
    final monday = mondayOf(todayDate());
    expect(find.text(weekRangeText(monday)), findsOneWidget);
    for (var i = 0; i < 7; i++) {
      expect(find.text('${DateTime.parse(datePlus(monday, i)).day}'), findsWidgets);
    }
  });

  testWidgets('Splits tab shows its empty states with one button each', (tester) async {
    await _open(tester, Harness.ready());
    await _pill(tester, 'Splits');
    expect(find.text('Your splits'), findsOneWidget);
    expect(find.textContaining('No splits yet'), findsOneWidget);
    expect(find.textContaining('No templates yet'), findsOneWidget);
    expect(find.text('Create a split'), findsOneWidget);
    expect(find.text('New template'), findsOneWidget);
  });

  testWidgets('Exercises tab: cards show muscle, equipment and category; the muscle chips filter; archived ones hide', (tester) async {
    final h = Harness.ready();
    await h.local.applyPulled([
      pulled('muscles', 1, {'id': uid(1), 'key': 'upper_chest', 'label': 'Upper chest', 'group_key': 'chest'}),
      pulled('muscles', 2, {'id': uid(2), 'key': 'biceps', 'label': 'Biceps', 'group_key': 'arms'}),
      pulled('equipment', 3, {'id': uid(3), 'key': 'barbell', 'label': 'Barbell'}),
      pulled('exercises', 4, {'id': uid(4), 'name': 'Bench Press', 'category': 'compound', 'equipment_id': uid(3), 'is_custom': false}),
      pulled('exercises', 5, {'id': uid(5), 'name': 'EZ-Bar Curl', 'category': 'isolation', 'is_custom': false}),
      pulled('exercises', 6, {'id': uid(6), 'name': 'Old Machine Press', 'category': 'compound', 'is_custom': true, 'removed_on': '2026-10-01'}),
      pulled('exercise_muscles', 7, {'id': uid(7), 'exercise_id': uid(4), 'muscle_id': uid(1), 'role': 'primary'}),
      pulled('exercise_muscles', 8, {'id': uid(8), 'exercise_id': uid(5), 'muscle_id': uid(2), 'role': 'primary'}),
    ], 8);
    await _open(tester, h);
    await _pill(tester, 'Exercises');

    expect(find.text('Browse and search movements'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Upper chest • Barbell'), findsOneWidget);
    expect(find.text('Compound'), findsOneWidget);
    expect(find.text('Isolation'), findsOneWidget);
    expect(find.text('Old Machine Press'), findsNothing);

    await _tap(tester, find.widgetWithText(InkWell, 'Arms'));
    expect(find.text('Bench Press'), findsNothing);
    expect(find.text('EZ-Bar Curl'), findsOneWidget);

    await _tap(tester, find.widgetWithText(InkWell, 'All'));
    expect(find.text('Bench Press'), findsOneWidget);

    await _tap(tester, find.widgetWithText(InkWell, 'Archived'));
    expect(find.text('Old Machine Press'), findsOneWidget);
    expect(find.text('Bench Press'), findsNothing);
  });

  testWidgets('Exercises tab: search narrows the list', (tester) async {
    final h = Harness.ready();
    await h.local.applyPulled([
      pulled('exercises', 1, {'id': uid(1), 'name': 'Front Squat', 'category': 'compound', 'is_custom': false}),
      pulled('exercises', 2, {'id': uid(2), 'name': 'Bench Press', 'category': 'compound', 'is_custom': false}),
    ], 2);
    await _open(tester, h);
    await _pill(tester, 'Exercises');
    await tester.enterText(find.byKey(const Key('exercise-search')), 'squat');
    await tester.pumpAndSettle();
    expect(find.text('Front Squat'), findsOneWidget);
    expect(find.text('Bench Press'), findsNothing);
  });

  testWidgets('History: a workout with no sets is flagged, and Dismiss discards it after a confirmation', (tester) async {
    final h = Harness.ready();
    final today = todayDate();
    await h.local.applyPulled([
      pulled('workout_sessions', 1, {
        'id': uid(7),
        'occurred_at': DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String(),
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'local_date': today,
        'status': 'completed',
        'name': 'Empty one',
      }),
    ], 1);
    await _open(tester, h);
    await _pill(tester, 'History');

    expect(find.text('Recent workouts'), findsOneWidget);
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('0 sets · not counted'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);

    await _tap(tester, find.text('Dismiss'));
    expect(find.text('Discard this workout?'), findsOneWidget);
    await _tap(tester, find.text('Keep it'));
    expect(await h.local.list('workout_sessions'), hasLength(1));

    await _tap(tester, find.text('Dismiss'));
    await _tap(tester, find.text('Discard'));
    expect(await h.local.list('workout_sessions'), isEmpty);
  });

  testWidgets('History: the Open dialog explains that the workout is not counted and offers Keep for now', (tester) async {
    final h = Harness.ready();
    await h.local.applyPulled([
      pulled('workout_sessions', 1, {
        'id': uid(7),
        'occurred_at': DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String(),
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'local_date': todayDate(),
        'status': 'completed',
      }),
    ], 1);
    await _open(tester, h);
    await _pill(tester, 'History');
    await _tap(tester, find.text('Open'));

    expect(find.text('Workout history'), findsOneWidget);
    expect(find.text('No sets logged'), findsOneWidget);
    expect(find.text('Resume workout'), findsOneWidget);
    expect(find.text('Discard workout'), findsOneWidget);
    expect(find.text('Discarding can’t be undone.'), findsOneWidget);

    await _tap(tester, find.text('Keep for now'));
    expect(find.text('Workout history'), findsNothing);
    expect(await h.local.list('workout_sessions'), hasLength(1));
  });

  testWidgets('Schedule: a day opens a dialog, and marking it as a rest day saves it', (tester) async {
    final h = Harness.ready();
    await _open(tester, h);
    await _pill(tester, 'Schedule');

    expect(find.text('Schedule · this week'), findsOneWidget);
    expect(find.text('No split active'), findsOneWidget);
    expect(find.text('Activate one to plan your week.'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);

    final monday = mondayOf(todayDate());
    await _tap(tester, find.byKey(Key('schedule-day-$monday')));
    expect(find.text(dateText(monday)), findsWidgets);
    expect(find.text('Unplanned day'), findsOneWidget);
    expect(find.text('+ Assign workout template'), findsOneWidget);
    expect(find.text('Activate a split →'), findsOneWidget);

    await _tap(tester, find.text('Mark as rest day'));
    final entries = await h.local.list('schedule_entries');
    expect(entries.single['is_rest_day'], true);
    expect(entries.single['local_date'], monday);
    expect(find.text('Rest day'), findsWidgets);
  });

  testWidgets('Schedule: "Activate a split" in the day dialog goes to the Splits tab', (tester) async {
    await _open(tester, Harness.ready());
    await _pill(tester, 'Schedule');
    await _tap(tester, find.byKey(Key('schedule-day-${mondayOf(todayDate())}')));
    await _tap(tester, find.text('Activate a split →'));
    expect(find.text('Your splits'), findsOneWidget);
  });

  testWidgets('Schedule: assigning a template plans a one-off workout, and today then offers Log workout', (tester) async {
    final h = Harness.ready();
    final container = await _open(tester, h);
    final exercise = await _exercise(container);
    await container.read(trainingManagementServiceProvider).createTemplate(name: 'Push day', exercises: [TemplateExerciseDraft(exerciseId: exercise, targetSets: 3, repMin: 8, repMax: 12)]);
    await tester.pumpAndSettle();
    await _pill(tester, 'Schedule');

    expect(find.byKey(const Key('schedule-log-workout')), findsNothing);
    await _tap(tester, find.byKey(Key('schedule-day-${todayDate()}')));
    await _tap(tester, find.text('+ Assign workout template'));
    expect(find.text('Choose a template'), findsOneWidget);
    await _tap(tester, find.text('Push day'));

    final entry = (await h.local.list('schedule_entries')).single;
    expect(entry['local_date'], todayDate());
    expect(entry['is_rest_day'], false);
    expect(entry['template_version_id'], isNotNull);
    expect(find.text('+ Log workout'), findsOneWidget);
    expect(find.textContaining('Push day'), findsWidgets);
  });

  testWidgets('Schedule: assigning a template with none made says so and plans nothing', (tester) async {
    final h = Harness.ready();
    await _open(tester, h);
    await _pill(tester, 'Schedule');
    await _tap(tester, find.byKey(Key('schedule-day-${mondayOf(todayDate())}')));
    await _tap(tester, find.text('+ Assign workout template'));
    expect(find.textContaining('You have no templates yet'), findsOneWidget);
    expect(await h.local.list('schedule_entries'), isEmpty);
  });

  group('reopening a finished workout', () {
    Future<(Harness, ProviderContainer, String)> finishedEmptyWorkout(WidgetTester tester) async {
      final h = Harness.ready();
      final container = await _open(tester, h);
      final exercise = await _exercise(container);
      final service = container.read(workoutSessionServiceProvider);
      final id = await service.startSession(name: 'Push');
      await service.addExercise(id, exercise);
      await service.completeSession(id);
      await tester.pumpAndSettle();
      return (h, container, id);
    }

    testWidgets('restores the skipped exercises and makes the workout active again', (tester) async {
      final (h, container, id) = await finishedEmptyWorkout(tester);
      expect((await h.local.list('workout_sessions')).single['status'], 'completed');
      expect((await h.local.list('session_exercises')).single['status'], 'skipped');

      await container.read(workoutSessionServiceProvider).reopenSession(id);
      final session = (await h.local.list('workout_sessions')).single;
      expect(session['status'], 'in_progress');
      expect(session['ended_at'], isNull);
      expect((await h.local.list('session_exercises')).single['status'], 'added');
    });

    testWidgets('refuses while another workout is running', (tester) async {
      final (_, container, id) = await finishedEmptyWorkout(tester);
      final service = container.read(workoutSessionServiceProvider);
      await service.startSession(name: 'Other');
      await expectLater(service.reopenSession(id), throwsA(isA<SessionAlreadyActive>()));
    });

    testWidgets('refuses a workout that has logged sets', (tester) async {
      final h = Harness.ready();
      final container = await _open(tester, h);
      final exercise = await _exercise(container);
      final service = container.read(workoutSessionServiceProvider);
      final id = await service.startSession(name: 'Push');
      final sessionExercise = await service.addExercise(id, exercise);
      await service.logSet(sessionExercise, weightKg: 60, reps: 8);
      await service.completeSession(id);
      await expectLater(service.reopenSession(id), throwsA(isA<StateError>()));
      expect((await h.local.list('workout_sessions')).single['status'], 'completed');
    });

    testWidgets('Resume workout in the dialog reopens it and opens the session screen', (tester) async {
      final (h, _, _) = await finishedEmptyWorkout(tester);
      await _pill(tester, 'History');
      await _tap(tester, find.text('Open'));
      await tester.tap(find.text('Resume workout'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect((await h.local.list('workout_sessions')).single['status'], 'in_progress');
      // The session screen has a running clock, so remove it before the test ends.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('assignTemplate', () {
    testWidgets('replaces an unfinished plan on the day and leaves a finished one alone', (tester) async {
      final h = Harness.ready();
      final container = await _open(tester, h);
      final management = container.read(trainingManagementServiceProvider);
      final exercise = await _exercise(container);
      final templateId = await management.createTemplate(name: 'Push day', exercises: [TemplateExerciseDraft(exerciseId: exercise, targetSets: 3, repMin: 8, repMax: 12)]);
      final version = (await container.read(trainingRepositoryProvider).currentVersionOfTemplate(templateId))!;

      await management.setScheduleDay('2026-11-12', rest: true);
      await management.assignTemplate('2026-11-12', version);
      final live = (await h.local.list('schedule_entries')).where((e) => e['local_date'] == '2026-11-12').toList();
      expect(live.single['is_rest_day'], false);
      expect(live.single['template_version_id'], version.id);

      await container.read(changeWriterProvider).upsert('schedule_entries', {'local_date': '2026-11-13', 'is_rest_day': false, 'status': 'completed', 'session_id': uid(99)});
      await expectLater(management.assignTemplate('2026-11-13', version), throwsA(isA<ManagementError>()));
      await expectLater(management.assignTemplate('not-a-date', version), throwsA(isA<ManagementError>()));
    });
  });
}
