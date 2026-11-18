# Phone and watch steps through Health Connect

Branch suggestion: `integration/steps-health-connect`. Nothing under `backend/` or `shared/` changed (steps use the existing `daily_steps` table and its `device_import` source).
**Not compiled or run here (no Flutter SDK, no phone).** Plugin calls follow the `health` package documentation; `flutter pub get`, `flutter analyze` and `flutter test` are the real check.

## How it works
Google Health (the renamed Fitbit app), a watch app or Samsung Health write steps into Android Health Connect. Health Connect combines them. The app reads the combined daily total (read-only, steps only) and saves it with `LifestyleService.setSteps(..., source: 'device_import')`, so it works offline and syncs like any entry.

## Rules
- Imported total replaces an earlier imported total for that day.
- A day with source `manual` is never overwritten. Typing a day over an imported one locks it.
- An unchanged value is not written again. A zero day with no record gets no row.
- Today is read from midnight to now; the six days before it are re-read each time (a late watch sync fixes them).
- Access is requested only when the owner taps "Connect steps". The background runner (app open, resume, every 5 minutes while open) never prompts.

## Files
New: `features/lifestyle/data/{step_source,health_connect_step_source,step_import_service,step_providers}.dart`, `features/lifestyle/presentation/{step_import_card,step_import_runner}.dart`, `test/step_import_test.dart`.
Changed: `main.dart`, `AndroidManifest.xml` (READ_STEPS, Health Connect queries, rationale screen), `MainActivity.kt` (FlutterFragmentActivity), `build.gradle.kts` (minSdk 26).
The `pubspec.yaml` and `lifestyle_screen.dart` edits are included too (below).

## Manual edits (already applied in this patch)
1. `cd application && flutter pub add health` (lets pub choose a version that fits your Flutter SDK).
2. `lib/features/lifestyle/presentation/lifestyle_screen.dart`: add `import 'step_import_card.dart';` and change the Activity tab (case 4) to
   `return const [_StepsCard(), StepImportCard(), _LogCardio(), _WaterCard()];`
   Also change the steps card note "Entered by hand for now. Phone step counting is added later as another source." to "Type a day by hand, or connect Health Connect below."

## Phone test steps
1. Install Google Health and sign in with the watch or phone; confirm it shows steps. In Health Connect, App permissions, check Google Health can write steps.
2. `flutter run --dart-define-from-file=dart_defines.json`. Lifestyle, Activity, tap "Connect steps", allow Steps.
3. Today's steps and the last days appear in the Steps card. Compare with the Google Health app.
4. Type a number for a past day: it stays after "Update steps now".
5. Airplane mode: tap "Update steps now"; the day saves and "N waiting" syncs later.
6. Deny permission: the card stays on "Connect steps" and nothing is saved.

## Watch for
- If the permission screen does not open, tell me; some `health` versions also need the Activity Recognition runtime permission (`permission_handler`).
- Android 9 to 13 need the Health Connect app from Play Store; Android 14+ has it built in.
- Without access, Health Connect only returns the last 30 days, and nothing is read before you grant.
