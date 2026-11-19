# Workout Calendar and historical workout logging

Training → Overview has a calendar icon (top right). It opens `/training/calendar`.

## Calendar
Monthly grid, Monday first, previous/next month, today outlined, selected day highlighted, legend below.
Status per date (`workoutDayStatus`, pure and tested), using plain `YYYY-MM-DD` strings only:

| Status | Rule | Look |
|---|---|---|
| completed | a finished session with logged working sets exists, or the day's schedule entry is completed | green |
| missing | past, planned workout (not rest), entry still `planned`, nothing recorded | red |
| skipped | schedule entry marked `skipped` | neutral |
| rest | scheduled rest day | neutral |
| scheduled | planned for today or later (never missing) | neutral |
| unscheduled | no entry, or the plan was rescheduled elsewhere | neutral |

Long-press a red day → "Mark skipped" (existing `markDaySkipped`).

## Tapping a day (all through the existing workout screen)
- Completed → edit mode on the existing session (no new session).
- Missing / skipped / rest / unplanned past day → create mode, dated to that day; the planned template's exercises are loaded when the day has a plan, otherwise exercises are added with the normal "Add exercise" list.
- Today → the normal live workout (unchanged). Future days → a message, nothing is created.

## Changes to existing code
- `WorkoutSessionScreen` takes optional `WorkoutLogArgs(selectedDate, mode: create|edit, sessionId)` (via the route's `extra`). With no args it behaves exactly as before. In calendar mode there is no clock, pause or rest timer; "Save workout"/"Save changes" (and the back button) save and return. Set rows can be tapped to correct weight/reps.
- `WorkoutSessionService.startHistoricalSession(date, …)`: a completed session stamped at noon of that day (so the date cannot drift across time zones, `local_date` and `tz_offset_minutes` set as for every event), template exercises copied; an empty leftover session on that date is replaced, so dates never collect duplicates. `completeSession` gained `endedAt` (the end is the dated time, not now) and then links the schedule entry as before.
- `TrainingRepository.calendarDays/finishedSessionsBetween`, `workoutCalendarProvider(YYYY-MM)` (reloads on every local change, so the calendar updates after saving).
- No new tables, no new sync path: everything goes through `ChangeWriter`, the outbox and the existing sync.

## Assumptions
- A session with no logged working sets does not turn a day green (same rule as the Training week strip), unless the day's plan was completed from Home.
- If a day has several workouts, edit opens the one with logged sets.
- Leaving a new calendar workout with no sets discards it.
- Editing can remove every set; the session then no longer counts.

## Not verified
Not compiled or run (no Flutter SDK here). Run `flutter pub get && dart format . && flutter analyze && flutter test`.
