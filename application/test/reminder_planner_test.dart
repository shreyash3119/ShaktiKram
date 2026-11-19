import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/notifications/reminder_planner.dart';
import 'package:shaktikram/core/notifications/reminder_settings.dart';

void main() {
  final now = DateTime(2026, 11, 19, 10, 0); // a Thursday
  PlannedWorkout day(int offset, [String name = 'Push']) =>
      PlannedWorkout(date: DateTime(2026, 11, 19 + offset), name: name);

  group('planReminders', () {
    test('a training day gets a workout reminder and a leave-for-gym nudge before it', () {
      final r = planReminders(settings: const ReminderSettings(supplements: false, reassessment: false), workouts: [day(0)], now: now);
      expect(r.map((e) => e.title), ['Time to train', 'Time to leave for the gym']);
      expect(r[0].at, DateTime(2026, 11, 19, 18, 0));
      expect(r[1].at, DateTime(2026, 11, 19, 17, 15));
      expect(r.every((e) => e.repeat == ReminderRepeat.none), isTrue);
    });

    test('past days, and days beyond the horizon, are left out', () {
      final r = planReminders(
        settings: const ReminderSettings(supplements: false, reassessment: false),
        workouts: [day(-1), day(reminderHorizonDays), day(1)],
        now: now,
      );
      expect(r.length, 2);
      expect(r.first.at.day, 20);
    });

    test('a workout time that has already passed today is skipped', () {
      final late = DateTime(2026, 11, 19, 17, 30);
      final r = planReminders(settings: const ReminderSettings(supplements: false, reassessment: false), workouts: [day(0)], now: late);
      expect(r.map((e) => e.title), ['Time to train']); // the 17:15 nudge has passed
    });

    test('switched-off reminders are not planned', () {
      final r = planReminders(
        settings: const ReminderSettings(workout: false, leaveForGym: false, supplements: false, water: false, reassessment: false),
        workouts: [day(0), day(1)],
        now: now,
      );
      expect(r, isEmpty);
    });

    test('supplements repeat daily from the next time that is still ahead', () {
      final r = planReminders(settings: const ReminderSettings(workout: false, leaveForGym: false, reassessment: false), workouts: const [], now: now);
      expect(r.single.repeat, ReminderRepeat.daily);
      expect(r.single.at, DateTime(2026, 11, 20, 9, 0)); // 9:00 today has passed
    });

    test('water gives seven daily reminders between 9 am and 9 pm', () {
      final r = planReminders(
        settings: const ReminderSettings(workout: false, leaveForGym: false, supplements: false, reassessment: false, water: true),
        workouts: const [],
        now: now,
      );
      expect(r.length, 7);
      expect(r.map((e) => e.at.hour).toList()..sort(), [9, 11, 13, 15, 17, 19, 21]);
      expect(r.first.at, DateTime(2026, 11, 20, 9)); // already past today
      expect(r[1].at, DateTime(2026, 11, 19, 11));
      expect(r.map((e) => e.id).toSet().length, 7);
    });

    test('the weekly check-in is the coming Sunday at 10:00', () {
      final r = planReminders(settings: const ReminderSettings(workout: false, leaveForGym: false, supplements: false), workouts: const [], now: now);
      expect(r.single.repeat, ReminderRepeat.weekly);
      expect(r.single.at, DateTime(2026, 11, 22, 10));
      expect(r.single.at.weekday, DateTime.sunday);
    });

    test('ids are unique', () {
      final r = planReminders(
        settings: const ReminderSettings(water: true),
        workouts: [day(0), day(1), day(2)],
        now: now,
      );
      expect(r.map((e) => e.id).toSet().length, r.length);
    });
  });

  group('reminder settings', () {
    test('changes are written to the store and read back', () {
      final store = MemoryReminderStore();
      final c = ProviderContainer(overrides: [reminderStoreProvider.overrideWithValue(store)]);
      addTearDown(c.dispose);
      c.read(reminderSettingsProvider.notifier)
        ..setWater(true)
        ..setWorkoutMinutes(19 * 60 + 30);
      final c2 = ProviderContainer(overrides: [reminderStoreProvider.overrideWithValue(store)]);
      addTearDown(c2.dispose);
      final s = c2.read(reminderSettingsProvider);
      expect(s.water, isTrue);
      expect(s.workoutMinutes, 19 * 60 + 30);
      expect(s.workout, isTrue); // default
    });
  });

  test('reminderClock formats 12-hour times', () {
    expect(reminderClock(0), '12:00 am');
    expect(reminderClock(18 * 60 + 5), '6:05 pm');
    expect(reminderClock(12 * 60), '12:00 pm');
  });
}
