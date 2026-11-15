# Training UI, stage 1: the five tabs and the two dialogs

Built from the design images in `training_screen.zip` (Overview, Splits, Exercises, History, Schedule, History details,
Schedule details). Stage 2 is the editors (New split, New template, Add exercise, Edit exercise, Exercise details) and
stage 3 is the Workout session screen. Those screens are unchanged by this stage.

> Nothing here has been compiled or run: there is no Flutter SDK in the environment this was written in. Run
> `flutter pub get`, `dart format .`, `flutter analyze` and `flutter test` first.

## What changed, per design

| Design | Change |
|---|---|
| Overview | Today card with two buttons when nothing is planned ("Start empty workout", "Go to Schedule"). "This week" shows each day's date with Done (green, tick) and Missed (red, cross) states, today outlined, and the week range. Order is Today, This week, Active split, Quick actions (New template, Add exercise), Recent activity. The monthly totals card is gone (its figures moved to History). |
| Splits | "Your splits" and "Templates" cards with an icon tile and the empty-state sentence, and one full-width button each. |
| Exercises | The screen title becomes "Exercises / Browse and search movements". Search and a "+ New" button on one row, a scrolling row of muscle-group chips, and one card per exercise (icon, name, primary muscle and equipment, Compound or Isolation badge). |
| History | Stats card (workouts, volume, streak in weeks), a period menu (7, 30, 90 days, all time), a card per workout with duration, volume and up to three exercises, and an amber card for a workout with no sets (Open, Dismiss). |
| Schedule | Week chips (dot for activity, dash for nothing), a banner (Activate, or "Plan 4 weeks" once a split is active), then this week's seven days. Past days are dimmed and today has "+ Log workout". |
| History details | A centred dialog. A workout with no sets: warning, Resume workout, Keep for now, Discard workout. A workout with sets: totals and exercises. |
| Schedule details | A centred dialog: Assign workout template, Mark as rest day, Activate a split, Dismiss. |

## Rules used where the design left room

- **Done and Missed days.** A day is Done when a finished workout with logged sets exists on it, or its planned entry is
  completed. It is Missed when it is in the past and a workout was planned but not done, or its only workout has no
  logged sets. Rest days are never Missed. A workout with no sets never counts as Done.
- **Streak.** Consecutive weeks (Monday to Sunday) with at least one counted workout. A current week with no workout yet
  does not break it.
- **Volume and workout count** in History come from the server's session summaries (the same source the old monthly
  totals used); the status shows when they are not loaded, offline or out of date. The streak also counts workouts
  finished on this phone that have not synced.
- **Archived exercises.** The design drops the "show exercises not in use" switch, so archived exercises are reached with
  an "Archived" chip after the muscle-group chips.
- **Category and equipment filters** from the old library are not in the design and were removed from the list.
- **PR badge** on a history card is not shown: there is no per-workout record flag on the phone yet.

## New behaviour (not in the old code)

- `TrainingManagementService.assignTemplate(date, template)`: plans a one-off workout from a template with no split.
  A finished day is never replaced. Today's plan resolves this template, so Overview and Schedule can start it.
- `WorkoutSessionService.reopenSession(id)`: backs "Resume workout". Only for a finished workout with no logged working
  sets; restores exercises that were marked "Not done" and puts a linked schedule entry back to planned. Refused while
  another workout is running.

## Removed

`showScheduleDaySheet` (replaced by `showScheduleDay`), the 14-day schedule list, the "Schedule · this week" word grid and
its sentence about rest days, "Recent sessions", the monthly totals card, the exercise-library filters.

## Tests

New: `test/training_screens_test.dart`. Updated: `management_screens_test.dart` (New button, Open and Discard flow) and
`app_shell_test.dart` (Exercises and Schedule expectations).
