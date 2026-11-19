# Phone reminders (local notifications)

Reminders are scheduled **on the phone** with `flutter_local_notifications`, so they arrive with the app closed, with
sound and a pop-up banner. No server is involved and nothing is added to the database or `backend/`.

## What is sent

| Switch (Settings > Notifications) | When |
|---|---|
| Workout reminders | At the *Workout time* (default 6:00 pm) on each planned, not-yet-done training day in the next 14 days |
| Leave for gym | 45 minutes before that time, same days |
| Supplements | Every day at the *Supplement time* (default 9:00 am) |
| Water | Every day at 9, 11, 1, 3, 5, 7 and 9 (off by default) |
| Reassessment | Sundays at 10:00 am |

The switches and times are saved on the phone (`SharedPreferences`) and survive restarts. "Send a test notification"
asks for permission if needed and shows one at once.

The rest-timer Sound and Vibration switches are unchanged (they still only change the screen).

## How it works

- `core/notifications/reminder_planner.dart`: pure function that turns the settings and the planned days into a list of
  notifications. Tested in `test/reminder_planner_test.dart`.
- `notification_gateway.dart`: the phone side (channels with high importance = sound + heads-up banner, scheduling).
- `reminder_runner.dart`: rebuilds the pending list when the app is ready, when a switch or time changes, and whenever
  the app comes forward or goes to the background (so a schedule edited in the app is picked up).
- Android: `POST_NOTIFICATIONS` (asked on first start, Android 13+), `RECEIVE_BOOT_COMPLETED` (reminders return after a
  restart), core-library desugaring and a keep rule for release builds.

## Limits

- Reminders are inexact (no special alarm permission): Android may deliver one a few minutes late, more so in battery
  saver. Some makers (Xiaomi, Oppo, Vivo...) kill background apps; set ShaktiKram's battery use to "No restrictions".
- Training-day reminders cover the next 14 days and refresh each time the app is opened or left. If the app is not
  opened for two weeks they run out; the daily ones (supplements, water) and the weekly one repeat on their own.
- A workout already logged for the day is not detected until the app next refreshes (open or leave it).
- Android only (the app is Android only).
