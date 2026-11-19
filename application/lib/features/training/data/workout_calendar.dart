import 'training_models.dart';

/// What the Workout Calendar shows for one date. Skipped and rest look the same on screen but stay separate here.
enum WorkoutDayStatus {
  /// A workout was recorded (it has logged working sets, or the day's plan was marked completed).
  completed,

  /// In the past, a workout was planned, nothing was recorded and it was not marked skipped.
  missing,

  /// The planned workout was explicitly marked skipped.
  skipped,

  /// A rest day was planned.
  rest,

  /// Planned for today or later. Never missing.
  scheduled,

  /// Nothing planned (or the plan was moved to another day).
  unscheduled,
}

/// The status of [date] (`YYYY-MM-DD`). [entry] is the day's schedule entry, [hasCountedSession] whether a workout with
/// logged working sets exists on that date. Only plain date strings are compared, so no time zone can move a workout
/// to another day.
WorkoutDayStatus workoutDayStatus({
  required String date,
  required String today,
  required ScheduleEntry? entry,
  required bool hasCountedSession,
}) {
  if (hasCountedSession || entry?.status == 'completed') {
    return WorkoutDayStatus.completed;
  }
  if (entry == null) return WorkoutDayStatus.unscheduled;
  if (entry.status == 'skipped') return WorkoutDayStatus.skipped;
  if (entry.isRestDay) return WorkoutDayStatus.rest;
  if (entry.status == 'planned') {
    return date.compareTo(today) < 0
        ? WorkoutDayStatus.missing
        : WorkoutDayStatus.scheduled;
  }
  return WorkoutDayStatus.unscheduled;
}

/// One calendar date: its status, its schedule entry and the recorded session to open, if any.
class WorkoutCalendarDay {
  const WorkoutCalendarDay({
    required this.date,
    required this.status,
    this.entry,
    this.sessionId,
  });

  final String date;
  final WorkoutDayStatus status;
  final ScheduleEntry? entry;

  /// The finished session on this date (one with logged sets is preferred), or null.
  final String? sessionId;
}
