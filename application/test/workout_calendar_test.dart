import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/sync/change_writer.dart';
import 'package:shaktikram/features/training/data/training_models.dart';
import 'package:shaktikram/features/training/data/training_providers.dart';
import 'package:shaktikram/features/training/data/workout_calendar.dart';
import 'package:shaktikram/features/training/presentation/training_format.dart';

import 'support/fakes.dart';

ScheduleEntry _entry(String date, {String status = 'planned', bool rest = false}) =>
    ScheduleEntry(id: 'e-$date', localDate: date, status: status, isRestDay: rest);

Future<(Harness, ProviderContainer)> _open(WidgetTester tester) async {
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
  await tester.tap(find.byKey(const Key('nav-Training')));
  await tester.pumpAndSettle();
  return (h, container);
}

Future<void> _openCalendar(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('training-calendar')));
  await tester.pumpAndSettle();
}

/// Moves the calendar to the month of [date] (at most a few steps back).
Future<void> _showMonthOf(WidgetTester tester, String date) async {
  final d = DateTime.parse(date);
  final now = DateTime.parse(todayDate());
  var back = (now.year - d.year) * 12 + now.month - d.month;
  while (back-- > 0) {
    await tester.tap(find.byKey(const Key('calendar-prev')));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('status rules', () {
    const today = '2026-11-19';

    test('a recorded workout is completed', () {
      expect(
        workoutDayStatus(date: '2026-11-10', today: today, entry: null, hasCountedSession: true),
        WorkoutDayStatus.completed,
      );
    });

    test('a past planned day with no record is missing, today and the future never are', () {
      WorkoutDayStatus s(String d) => workoutDayStatus(
        date: d, today: today, entry: _entry(d), hasCountedSession: false);
      expect(s('2026-11-18'), WorkoutDayStatus.missing);
      expect(s('2026-11-19'), WorkoutDayStatus.scheduled);
      expect(s('2026-11-25'), WorkoutDayStatus.scheduled);
    });

    test('skipped and rest stay separate, and unplanned days stay neutral', () {
      expect(
        workoutDayStatus(date: '2026-11-10', today: today, entry: _entry('2026-11-10', status: 'skipped'), hasCountedSession: false),
        WorkoutDayStatus.skipped,
      );
      expect(
        workoutDayStatus(date: '2026-11-10', today: today, entry: _entry('2026-11-10', rest: true), hasCountedSession: false),
        WorkoutDayStatus.rest,
      );
      expect(
        workoutDayStatus(date: '2026-11-10', today: today, entry: null, hasCountedSession: false),
        WorkoutDayStatus.unscheduled,
      );
    });
  });

  testWidgets('month lengths and leap years', (tester) async {
    final (_, c) = await _open(tester);
    final repo = c.read(trainingRepositoryProvider);
    expect((await repo.calendarDays('2028-02-01', '2028-02-29', '2030-01-01')).length, 29);
    expect((await repo.calendarDays('2027-02-01', '2027-02-28', '2030-01-01')).length, 28);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the calendar opens from Training and moves between months', (tester) async {
    await _open(tester);
    await _openCalendar(tester);
    final now = DateTime.parse(todayDate());
    expect(find.byKey(const Key('calendar-month')), findsOneWidget);
    expect((tester.widget<Text>(find.byKey(const Key('calendar-month'))).data), contains('${now.year}'));
    final before = tester.widget<Text>(find.byKey(const Key('calendar-month'))).data;
    await tester.tap(find.byKey(const Key('calendar-next')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('calendar-month'))).data, isNot(before));
    await tester.tap(find.byKey(const Key('calendar-prev')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('calendar-month'))).data, before);
  });

  testWidgets('a future day cannot be logged', (tester) async {
    final (h, _) = await _open(tester);
    await _openCalendar(tester);
    await tester.tap(find.byKey(const Key('calendar-next')));
    await tester.pumpAndSettle();
    final next = DateTime.parse(todayDate());
    final date = DateTime(next.year, next.month + 1, 15).toIso8601String().substring(0, 10);
    await tester.tap(find.byKey(Key('cal-$date')));
    await tester.pumpAndSettle();
    expect(find.text('You can only log today or an earlier day.'), findsOneWidget);
    expect(await h.local.list('workout_sessions'), isEmpty);
  });

  testWidgets('a missing day is logged into the existing screen, saved to that date, then edited without a duplicate',
      (tester) async {
    final (h, c) = await _open(tester);
    final day = datePlus(todayDate(), -2);
    await c.read(changeWriterProvider).upsert('schedule_entries', {
      'local_date': day,
      'is_rest_day': false,
      'status': 'planned',
    });
    await tester.pumpAndSettle();
    expect(
      (await c.read(trainingRepositoryProvider).calendarDays(day, day, todayDate()))[day]!.status,
      WorkoutDayStatus.missing,
    );

    await _openCalendar(tester);
    await _showMonthOf(tester, day);
    await tester.tap(find.byKey(Key('cal-$day')));
    await tester.pumpAndSettle();

    // The same workout screen, dated to the chosen day, with nothing saved yet.
    // Nothing in it yet, so the Workout start page shows; add an exercise to it.
    expect(find.byKey(const Key('start-workout')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('picker-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start-workout')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('save-historical')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('kg-field')), '60');
    await tester.enterText(find.byKey(const Key('reps-field')), '8');
    await tester.tap(find.byKey(const Key('confirm-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-historical')));
    await tester.pumpAndSettle();

    final sessions = await h.local.list('workout_sessions');
    expect(sessions.length, 1);
    expect(sessions.single['local_date'], day);
    expect(sessions.single['status'], 'completed');
    expect((await h.local.list('sets')).length, 1);
    final entry = (await h.local.list('schedule_entries')).single;
    expect(entry['status'], 'completed');
    expect(entry['session_id'], sessions.single['id']);
    expect(
      (await c.read(trainingRepositoryProvider).calendarDays(day, day, todayDate()))[day]!.status,
      WorkoutDayStatus.completed,
    );

    // The calendar shows the change without a restart; tapping the day edits the same session.
    await tester.tap(find.byKey(Key('cal-$day')));
    await tester.pumpAndSettle();
    expect(find.text('Save changes'), findsWidgets);
    await tester.tap(find.byKey(const Key('edit-set-1-Working set 1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-kg-field')), '65');
    await tester.tap(find.byKey(const Key('edit-set-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-historical')));
    await tester.pumpAndSettle();

    expect((await h.local.list('workout_sessions')).length, 1);
    final sets = await h.local.list('sets');
    expect(sets.single['weight_kg'], 65);
  });

  testWidgets('backing out of a new day with nothing logged leaves nothing behind', (tester) async {
    final (h, _) = await _open(tester);
    final day = datePlus(todayDate(), -3);
    await _openCalendar(tester);
    await _showMonthOf(tester, day);
    await tester.tap(find.byKey(Key('cal-$day')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session-back')));
    await tester.pumpAndSettle();
    expect((await h.local.list('workout_sessions')).where((s) => s['deleted_at'] == null), isEmpty);
    expect(find.byKey(const Key('calendar-month')), findsOneWidget);
  });

  testWidgets('a missing day can be marked skipped and turns neutral', (tester) async {
    final (h, c) = await _open(tester);
    final day = datePlus(todayDate(), -2);
    await c.read(changeWriterProvider).upsert('schedule_entries', {
      'local_date': day,
      'is_rest_day': false,
      'status': 'planned',
    });
    await tester.pumpAndSettle();
    await _openCalendar(tester);
    await _showMonthOf(tester, day);
    await tester.longPress(find.byKey(Key('cal-$day')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skip-confirm')));
    await tester.pumpAndSettle();
    expect((await h.local.list('schedule_entries')).single['status'], 'skipped');
    expect(
      (await c.read(trainingRepositoryProvider).calendarDays(day, day, todayDate()))[day]!.status,
      WorkoutDayStatus.skipped,
    );
  });
}
