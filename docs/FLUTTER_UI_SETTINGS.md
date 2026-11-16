# Settings UI redesign

Settings is now a hub with five pages, as in the designs. Not compiled or run here (no Flutter SDK); run `flutter analyze` and `flutter test`.

| Design | Code |
|---|---|
| Hub: profile, backup banner, five rows, sync card, sign out, danger zone | `settings_screen.dart`; shared pieces in `settings_common.dart` |
| Workout & training | `/settings/training`: split and equipment rows (open Training), schedule days, defaults |
| Notifications | `/settings/notifications`: reminders and rest timer switches |
| Appearance | `/settings/appearance`: theme (works), units (metric only), app lock |
| Data & sync | `/settings/data`: sync with counts, backup banner, Export data, Backup & data export, debug sync check |
| Account | `/settings/account`: masked email with Show/Hide, this device, Manage devices, sign out, Clear data |

`ScreenFrame` gained an optional `leading` (the back button).

## Assumptions
- Still placeholders, as before: the profile numbers and Edit (shows "coming soon"), training days, reminder time, defaults, and all switches (kept while the app runs only).
- Clear data is still not available; it explains that and does nothing.
- The old inline "Edit profile" and "Training defaults" forms are gone from the hub.
- The email is masked until Show is tapped.
- Tests: Manage devices and the backup links are now reached through Account and Data & sync.
