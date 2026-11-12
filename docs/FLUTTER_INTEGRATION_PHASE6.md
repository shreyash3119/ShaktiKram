# Phase 6 — Lifestyle on real data

Branch `integration/phase6-lifestyle` (off `integration/phase5b-training-screens`). Nothing in `backend/` or `shared/` was touched.
Not compiled or run here (no Flutter SDK in this environment): run `flutter pub get`, `flutter analyze`, `flutter test`.

## 6a — data layer (`lib/features/lifestyle/data/`)
- `lifestyle_models.dart`, `lifestyle_repository.dart` (reads SQLite only), `lifestyle_service.dart` (all writes, via `ChangeWriter`),
  `lifestyle_providers.dart` (reload on `dataRevisionProvider`).
- Covers: daily check-in, sleep, steps, water, cardio, body measurements, injuries (+ updates), pain entries, restrictions,
  supplements (+ phases, logs), meals, meal plan entries, personal targets, body regions (read).
- Values are checked client-side against the Stage 3 constraints (ranges, vocabularies, "custom needs a name", body-fat needs a
  method, injury cannot be resolved before it started, replaced meal needs a replacement, unique supplement name).
- One check-in and one step count per day (database unique indexes): saving again edits the existing record.
- Versioned tables (`supplement_phases`, `personal_targets`) are written with `new_version`; values not given are carried over.
- **Core fix:** `new_version` changes were not visible locally until synced. Both stores now show the new version at once
  (`overlayNewVersion`); readers take the highest version as current. A refused version disappears. Contract test added.
- Fake server now enforces the Stage 3 rules above; `test/lifestyle_test.dart` round-trips each group through a real sync.

## 6b — screens (`lifestyle_screen.dart`)
- Overview: today's tiles (sleep, meals, water, steps), daily check-in, hydration, quick-log shortcuts.
- Recovery: sleep log, injuries (add / recovering / resolved), pain check-in, restrictions (add / end).
- Nutrition: today's plan (tap to mark eaten), add meal (+ log as eaten), saved meals (plan today), targets.
- Supplements: today (Taken / Skipped / Pause-Resume), add supplement.
- Activity: steps, cardio log + recent, hydration.
- The readiness card stays marked "Sample values" and shows no numbers: it is backend-calculated (Phase 7).

## Decisions taken (change if you disagree)
1. Nutrition totals on the Nutrition tab are simple sums of the meals you marked eaten, labelled as "so far" and flagged when
   estimates are included. If the backend's daily nutrition view should be the source, that moves to Phase 7.
2. Sleep is logged by hours slept (saved under the wake-up day), not bed/wake times; the service also accepts times.
3. Replacing a planned meal with another one is in the service (`setMealStatus(... replaced ...)`) but not on screen yet.

## Not done / pending
- Muscle assessments/priorities, meal ingredients/components, reminders, weekly meal plan view, body-measurement screen
  (weight is on Home), supplement history/phase list, restrictions matched to exercises (D29).
- Phone step counting (separate source adapter, section 11 of the plan) is not started.
- Backend Requests: none new.
