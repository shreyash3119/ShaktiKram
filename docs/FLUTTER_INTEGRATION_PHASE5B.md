# Phase 5b — Training screens on real data

Branch `integration/phase5b-training-screens` (off `phase5a-training-data`). Nothing in `backend/` or `shared/` was touched.
Not compiled or run here (no Flutter SDK in this environment): run `flutter pub get`, `flutter analyze`, `flutter test`.

## What changed
- **Workout session screen** reads and writes through `activeSessionProvider`, `sessionDetailProvider`,
  `previousPerformanceProvider` and `WorkoutSessionService`. No Supabase calls from the UI.
  - No workout running: start an empty one or from a current template.
  - Sets are saved to SQLite + outbox the moment they are confirmed (weight, reps, warm-up/working, optional RIR/RPE,
    rest seconds). Remove a set with the × on its row.
  - Add / skip / restore / remove exercise; pause/resume; workout note; Finish → summary from local totals;
    Discard (confirmed) soft-deletes the session.
  - "Previous" and the prefilled weight are the last finished session's logged sets. No suggestions are computed on the phone.
- **Training screen**: Today card (Start/Continue, uses today's schedule entry and its template), This week, Recent
  sessions, Active split, Splits/Templates (read-only), Exercise library with search, History with a session detail
  sheet, Schedule (this week). `startOrContinueWorkout()` is the shared entry point.
- Provider added: `scheduleWeekProvider`.
- Tests: `workout_session_test.dart` rewritten; `app_shell_test.dart` History expectation updated.

## Decisions taken (change if you disagree)
1. Save & exit leaves the workout open. A pause only exists while the screen is open: leaving the screen (Save & exit) or
   finishing ends it and adds the time paused to `paused_seconds`, so the saved workout is never left "paused" with an unknown
   start (fix for review item P5B-01). If the app is closed while paused, the database cannot say when the pause began; the
   next time the workout opens it goes back to in progress, the clock keeps running and the screen says the pause time was not
   recorded. Nothing is guessed.
2. Finishing marks untouched exercises "Not done" (service default).
3. Discard = soft delete of sets, exercises and session.

## Not done / pending
- Replace exercise and alternatives (needs D29 restriction matching), per-exercise notes, muscles, compare sessions,
  split/template/exercise editing.
- Monthly insights card is still "Sample values" (backend-derived, Phase 7).
- Home's "Start workout" still opens the session screen through the design-pass card (Phase 7).
- Backend Request (optional, for P5B-01 to survive an app kill): a pause-start timestamp on `workout_sessions` (for example
  `paused_at timestamptz`, set when status becomes `paused`, cleared on resume) so the paused interval can be recovered after a
  restart. Not invented on the Flutter side; the screen will use it once the contract has it. F5 (next-target caching) and D29 remain open.
