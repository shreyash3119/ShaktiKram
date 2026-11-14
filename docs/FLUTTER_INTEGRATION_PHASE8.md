# Flutter integration, phase 8: Stage 5 reporting service

Connects the Flutter app to the Stage 5 FastAPI service (`backend/fastapi`): report summaries, Excel and PDF
exports, full backup, CSV export and backup validation.

> **Verification status.** This work was written in an environment without the Flutter SDK. `dart format`,
> `flutter analyze` and `flutter test` have **not** been run on it, and the app has not been run against a live
> reporting service. Only a bracket and string balance check ran on each changed file. Run the commands under
> "Testing" first; expect to fix some compile errors or lint findings.

## Data flow

```
Screen -> Riverpod provider -> ReportRepository -> insight_cache (SQLite) -> ReportingGateway -> FastAPI
```

- Reports are read-only HTTP calls. They do not use `ChangeWriter`, the outbox or `SyncEngine`, and nothing from
  the reporting service is written to the synced tables.
- The server calculates every figure. The phone shows it and caches the last answer per period.
- The screens never call Supabase directly.

## What was implemented

**Foundation**
- `REPORT_API_URL` build setting; `AppConfig.checkReportUrl` requires `https` (plain `http` only for localhost,
  `10.0.2.2`, `.local` and private network addresses).
- `AuthService.accessToken({forceRefresh})`: returns the Supabase access token, refreshing it when expired or within
  60 seconds of expiry.
- `HttpReportingGateway`: bearer token on every call, one forced token refresh and retry after a 401, timeouts,
  streamed downloads to disk (`.part` file, renamed when complete, never overwriting an earlier file), multipart
  upload for validation. `{"detail": ...}` errors (string or FastAPI list) become `ReportError` with a message.
- Without `REPORT_API_URL` the app starts normally and the report screens say reports are not set up.

**Data**
- Typed models for the real summary JSON (`report_models.dart`), parsed defensively; missing sections become empty.
- `ReportQuery` (daily, weekly, monthly, quarterly, half-yearly, yearly, custom, complete) with validation that mirrors
  the service (year 1900 to 2200, custom range at most 3660 days), stepping and the service's own labels.
- `ReportRepository`: saves each summary in the existing `insight_cache` table, keyed by period and comparison choice.
  Fresh for 15 minutes. When the service cannot be reached the saved summary stays on screen with its age; it is never
  erased by a failed refresh.
- Export history: local-only SQLite table `export_log` (database version 4, additive migration; no user data touched,
  not synced).

**Screens**
- Reports: tabs Overview, Workouts, Strength, Body, Lifestyle, Goals and Export. Period selector with all eight kinds,
  previous and next stepping (next is disabled when it would start in the future), a date range picker for custom,
  and a comparison switch (previous period).
- Status line: "Calculated by the server. Updated N min ago", offline or error text with the age of the shown
  report, and a Refresh link.
- A notice when this phone has changes that have not synced, because reports only include server data.
- Estimated values (strength, body composition, nutrition) and the user's own muscle ratings are labelled as such.
  Observations carry a "not medical advice" line. Injury rows flagged by the service say a professional review is
  suggested.
- Empty, loading, error, offline, not configured and future-period states.
- Export tab: Excel and PDF for the selected period, with progress, errors, share/open and a history of saved files.
- Backup screen (`/settings/backup`): full backup, CSV data export (labelled "not a backup, cannot be restored"),
  "Include photos and media" switch (**off by default**, with a warning that media backup is not confirmed to work),
  validation of a chosen `.zip` through the real multipart endpoint (shows verdict, errors, warnings, counts, export
  date, format version), the date of the last full backup made from this phone, and an explanation that restoring is
  not available in the app.
- Settings: "Export data" opens the Reports Export tab, "Backup & data export" opens the Backup screen. The earlier
  claims of local or automatic backups (and the Restore and Back up now placeholders) were removed.

**Removed:** sample statistics, the export category selector, the fake export history and every placeholder button on
the Reports screen.

## Configuration

Build-time setting (never commit real values; `dart_defines.json` is ignored by git):

```json
{
  "SUPABASE_URL": "https://YOUR-PROJECT.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_...",
  "REPORT_API_URL": "https://YOUR-REPORTING-SERVICE.example.com"
}
```

Run with `flutter run --dart-define-from-file=dart_defines.json` (the same for `flutter build apk`).

- The address is the service root, without `/api/v1`.
- Android release builds need `https`. Debug builds also allow `http` to a computer on your network (the debug manifest
  sets `usesCleartextTraffic`); for an emulator use `http://10.0.2.2:8000`, for a phone on the same Wi-Fi use the
  computer's LAN address, for example `http://192.168.1.20:8000`, and start the service with `--host 0.0.0.0`.
- `INTERNET` permission was added to the main Android manifest.
- Packages added to `pubspec.yaml`: `http`, `path_provider`, `share_plus`, `file_picker`.

Backend environment (see `backend/fastapi/.env.example`): `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` (see blocker B2),
plus the service's database settings. The Flutter app only ever holds the publishable key and the user's own access
token.

## Testing

```bash
cd application
flutter pub get
dart format .
flutter analyze
flutter test
```

New or changed tests: `report_data_test.dart` (JSON parsing, periods, URL check), `reporting_gateway_test.dart`
(requests, headers, retry after 401, error mapping, timeouts, downloads, validation upload),
`report_repository_test.dart` (caching, stale and offline, export service, history, last backup),
`reports_screen_test.dart` (Reports, Export, Settings and Backup screens), and `app_shell_test.dart` (updated Reports
expectation).

### Phone checklist

1. Start the reporting service and make sure the phone can reach `REPORT_API_URL` (open `/api/v1/health` in the phone
   browser).
2. Install with the dart-defines above and sign in as the owner.
3. Reports > Overview: the current month loads and the status line says "Calculated by the server".
4. Step to earlier months, try Day, Week, Quarter, Half-year, Year, Custom and All time.
5. Switch on the comparison; the Overview shows the previous period and changes.
6. Visit Workouts, Strength, Body, Lifestyle and Goals. Check that an empty workout does not appear as an achievement
   (see R3 below).
7. Log a workout offline, open Reports: the "not synced yet" notice shows; tap Sync now when online.
8. Turn on flight mode: the last loaded period still shows with its age; a period never loaded says you are offline.
9. Export tab: download Excel and PDF, open or share them; they appear under "Saved on this phone".
10. Settings > Backup & data export: make a full backup and a CSV export; check the last backup date; share the zip.
11. Choose the backup zip under "Check a backup file": verdict, counts and warnings appear.
12. Leave "Include photos and media" off. Turning it on is expected to fail until B3 is fixed.
13. Stop the service: every action shows a readable error and nothing crashes.

## Known limitations

- Restore is command line only (`backend/scripts/restore_backup.py`). The app never restores.
- No automatic backups. The "last backup" date only covers backups made by this app on this phone.
- Saved exports live in the app's own storage and are removed when the app is uninstalled; share or move them out.
- Cached reports are per period; a period never opened while online is not available offline.
- Large backups are streamed to disk, but the service still builds the zip in memory, so very large datasets can be
  slow or fail on a small server.

## Backend dependencies and blockers (not changed here)

- **B1:** nothing in the repository deploys the service; an HTTPS address reachable from the phone is needed.
- **B2:** `.env.example` and `routes/backup.py` use `SUPABASE_ANON_KEY` while `config.py` and `auth.py` use
  `SUPABASE_PUBLISHABLE_KEY`. Following `.env.example` leaves the key empty and every call returns 401.
- **B3:** `include_media=true` reads the nonexistent `settings.SUPABASE_ANON_KEY` and returns a 500.
- **R3:** `training.sessions` and the Excel sessions sheet count every `completed` session from `v_session_summary`,
  including sessions with no sets. Suggested fix: filter on `working_sets > 0`. Until then a report can count a
  workout with no logged sets, and the app shows the server's number as it is.
- The status documents still list Stage 5 verification as pending.
