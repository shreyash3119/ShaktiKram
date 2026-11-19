import 'reminder_settings.dart';

enum ReminderRepeat { none, daily, weekly }

/// One notification to hand to the phone: first fires at [at] (phone time) and then repeats as [repeat] says.
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.channel,
    required this.title,
    required this.body,
    required this.at,
    this.repeat = ReminderRepeat.none,
  });

  final int id;
  final ReminderChannel channel;
  final String title;
  final String body;
  final DateTime at;
  final ReminderRepeat repeat;
}

enum ReminderChannel {
  workout('workout_reminders', 'Workout reminders', 'Training days and leaving for the gym'),
  supplements('supplement_reminders', 'Supplements', 'When a supplement dose is due'),
  water('water_reminders', 'Water', 'Hydration reminders through the day'),
  progress('progress_reminders', 'Progress check-in', 'Periodic progress check-in'),
  test('test_notifications', 'Test', 'Test notification from Settings');

  const ReminderChannel(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;
}

/// A training day still to do: its date and what to call it.
class PlannedWorkout {
  const PlannedWorkout({required this.date, required this.name});

  final DateTime date; // the calendar day (time of day ignored)
  final String name;
}

/// How many days ahead one-off (training day) reminders are set. The list is rebuilt every time the app opens or leaves
/// the screen, so it keeps rolling forward.
const reminderHorizonDays = 14;

/// Leave-for-gym nudge: this long before the workout reminder time.
const leaveBeforeMinutes = 45;

const waterHours = [9, 11, 13, 15, 17, 19, 21];

String reminderClock(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'am' : 'pm'}';
}

/// Works out every notification that should be pending, from the choices in Settings and the planned training days.
/// Pure: nothing is scheduled here, so it is easy to test.
List<PlannedReminder> planReminders({
  required ReminderSettings settings,
  required List<PlannedWorkout> workouts,
  required DateTime now,
}) {
  final out = <PlannedReminder>[];
  final today = DateTime(now.year, now.month, now.day);

  DateTime at(DateTime day, int minutes) => DateTime(day.year, day.month, day.day, 0, minutes);

  /// The next time of day [minutes] that is still ahead of [now].
  DateTime nextDaily(int minutes) {
    final t = at(today, minutes);
    return t.isAfter(now) ? t : at(today.add(const Duration(days: 1)), minutes);
  }

  final sorted = [...workouts]..sort((a, b) => a.date.compareTo(b.date));
  var n = 0;
  for (final w in sorted) {
    final day = DateTime(w.date.year, w.date.month, w.date.day);
    final offset = day.difference(today).inDays;
    if (offset < 0 || offset >= reminderHorizonDays) continue;
    final start = at(day, settings.workoutMinutes);
    if (settings.workout && start.isAfter(now)) {
      out.add(PlannedReminder(
        id: 1000 + n,
        channel: ReminderChannel.workout,
        title: 'Time to train',
        body: '${w.name} is planned for ${offset == 0 ? 'today' : 'this day'}. Open ShaktiKram to start.',
        at: start,
      ));
    }
    final leave = start.subtract(const Duration(minutes: leaveBeforeMinutes));
    if (settings.leaveForGym && leave.isAfter(now)) {
      out.add(PlannedReminder(
        id: 2000 + n,
        channel: ReminderChannel.workout,
        title: 'Time to leave for the gym',
        body: '${w.name} starts at ${reminderClock(settings.workoutMinutes)}.',
        at: leave,
      ));
    }
    n++;
  }

  if (settings.supplements) {
    out.add(PlannedReminder(
      id: 3000,
      channel: ReminderChannel.supplements,
      title: 'Supplements',
      body: 'Time to take your supplements.',
      at: nextDaily(settings.supplementMinutes),
      repeat: ReminderRepeat.daily,
    ));
  }

  if (settings.water) {
    for (var i = 0; i < waterHours.length; i++) {
      out.add(PlannedReminder(
        id: 4000 + i,
        channel: ReminderChannel.water,
        title: 'Drink some water',
        body: 'Log it in Lifestyle once you have.',
        at: nextDaily(waterHours[i] * 60),
        repeat: ReminderRepeat.daily,
      ));
    }
  }

  if (settings.reassessment) {
    // Sundays, 10:00.
    var d = today;
    while (d.weekday != DateTime.sunday || !at(d, 10 * 60).isAfter(now)) {
      d = d.add(const Duration(days: 1));
    }
    out.add(PlannedReminder(
      id: 5000,
      channel: ReminderChannel.progress,
      title: 'Weekly check-in',
      body: 'Take a minute to log your measurements and review your progress.',
      at: at(d, 10 * 60),
      repeat: ReminderRepeat.weekly,
    ));
  }
  return out;
}
