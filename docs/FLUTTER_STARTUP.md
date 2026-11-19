# Startup time

## What the launch did (before)
1. Android native launch screen.
2. `main()` awaited, one after the other: `Supabase.initialize`, `SharedPreferences.getInstance`, `SqfliteLocalStore.open` (opens the database; migrations only on first run or upgrade).
3. `runApp`; the session controller reads the device store (milliseconds, no network when a session and registration are stored), and the router showed the Flutter `SplashScreen` ("Starting…" spinner) until it finished, then moved to Home.
4. After the app is ready, sync and the Health Connect import start (unawaited, as before).

## What changed
- `main.dart`: the three independent set-up steps now run together (`Future.wait`); the wait is the slowest of them instead of the sum. Same calls, same arguments, same error behaviour.
- `main.dart`: `deferFirstFrame()` until the session phase is known and the router has applied its redirect (`_FirstFrameGate`), so the native launch screen is followed directly by Home (or sign-in). A 3-second safety timer releases it if the check ever stays unfinished; a start-up failure releases it too. No artificial delay.
- `splash_screen.dart`: the Flutter splash route no longer draws a spinner or text (it still exists as the session machine's "checking" location, so `sessionRedirect` and its tests are unchanged).

## Not changed
Database, schema, migrations, reads and writes; sync, triggers, retries; Supabase/backend/repositories; Riverpod providers; navigation; every screen and theme. `SyncRunner` and `StepImportRunner` still start exactly as before.

## Not measured
There is no Flutter SDK or device here, so I have no before/after numbers and nothing was run. To compare, on a release build:
`flutter run --release --trace-startup --profile` (writes `build/start_up_info.json`, `timeToFirstFrameMicros`) or `adb shell am start -W -n <package>/.MainActivity` (look at `TotalTime`), before and after the patch.

## What could still be slow (not touched)
`Supabase.initialize` restores the stored session and, when the access token has expired, may try to refresh it over the network. That is backend behaviour and was left alone. If startup is still slow on a device, that is the first thing to measure.
