# Flutter integration: Phase 5, part A (Training data layer)

Branch `integration/phase5a-training-data`, on top of Phase 4. Nothing under `backend/` or `shared/` was changed.
Phase 5 (Training) is delivered in two parts. This is part A: everything underneath the screens. Part B wires the Training and Workout screens to it.

## What the backend requires of the app (read from `20261107000500_sessions.sql`, `20261107000200_templates.sql`, `20261107000300_splits.sql`, `60_training_lifecycle.test.sql`)
- A session is `editable`; `session_exercises` are `editable`; **`sets` are append-only**, so fixing a set is a correction that must carry the set's current `base_rev` (the sync engine already does this).
- Completing a session is an edit with `status: completed` **and** `ended_at` (the database refuses one without the other). The linked schedule entry is edited to `completed` with its `session_id`.
- `set_type` is `warmup` or `working`; `(session_exercise_id, set_type, set_number)` and `(session_id, position)` are unique among live rows; RPE steps of 0.5; RIR 0 to 10.
- `local_date` must agree with `occurred_at` and `tz_offset_minutes` (otherwise `validation_failed`). All three now come from one instant (`core/time/local_stamp.dart`).
- A foreign-key failure comes back as `reference_missing`; the server applies a request's operations in `seq` order. A used template or split version is sealed (changes need a new version), and the server copies the prescription into a session exercise created from a template (the app never writes `prescription_snapshot`).
- Reordering exercises by swapping `position` would briefly collide on the unique index, so part A has no reorder. It needs a two-step move and comes with the screens if wanted.

## Added
1. **Atomic saves.** `LocalStore.saveLocalAll` and `ChangeWriter.apply(List<PendingChange>)` store and queue several changes as one step (a workout start is a session plus its exercises). All or none.
2. **`features/training/data/`**
   - `training_models.dart`: typed views of exercises, template versions and exercises (prescription), split and days, schedule entries, sessions, session exercises, sets, session totals.
   - `training_repository.dart`: reads from SQLite only: exercise library, muscles, current template versions and prescriptions, the active split with its days, a day's schedule entry, session history (newest first), the workout in progress, session detail, session totals, and the previous performance of an exercise.
   - `workout_session_service.dart`: start a workout (from a template or empty; one at a time), add, skip, restore and remove exercises, log, correct and delete sets, pause and resume, notes, complete (untouched exercises become "Not done"; the schedule entry is completed), discard. Entries are checked against the database's limits first, so a normal entry is never refused by the server.
   - `training_providers.dart`: Riverpod providers that reload when local data changes.
3. **Tests**
   - `test/training_test.dart`: reading the plan, a full offline workout that syncs cleanly (with warm-up and working sets, a skip, a pause, completion, schedule entry), corrections before and after sync, a freed set number reused, add/skip/restore/remove, "not done" on completion, discard, input checks, history and previous performance.
   - The fake server now also enforces the workout rules above (references, uniqueness, ranges, vocabularies, `local_date` consistency, the prescription copy), so a client mistake shows up as a failing test.
   - A contract test for `saveLocalAll` (runs on the in-memory store and on SQLite).

## Decisions to confirm
- **Totals shown in history (volume, working sets, duration) are worked out on the phone** from the sets it holds, with the same rules as the backend view `v_session_summary`. They are display only. Suggestions, readiness, records and other backend-dependent results stay on the backend and will be cached (Phase 7), as your rule says. If you want even these totals to come from the server, say so; the catch is they would not show offline.
- **Completing a workout marks exercises with no sets as skipped ("Not done").** This keeps `exercises_done` and `exercises_skipped` truthful. It is a parameter (`markUntouchedAsSkipped`) if you prefer otherwise.
- Discarding a workout deletes it (soft delete) rather than marking it `abandoned`.

## Not done in part A
Screens (part B), a reorder action, template and split editing, schedule editing, gym decisions and breaks, the session comparison and alternatives views.
The tests have not been run (no Flutter SDK here): `flutter pub get`, `flutter analyze`, `flutter test`.
