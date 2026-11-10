# Flutter architecture

Decisions F1 to F14 are in the project document `claude/flutter_app_decisions.md`. This file holds the rules the code follows.

## Stack
- Flutter, Android only. No web folder.
- State: Riverpod (`Notifier`, `NotifierProvider`, `Provider`, `FutureProvider`/`AsyncNotifier` for data).
- Navigation: go_router, `StatefulShellRoute.indexedStack` with one branch per section.
- Local database (step 4): SQLite through sqflite with hand-written SQL (Drift was dropped: it needs generated code that cannot be checked without the Flutter SDK). Auth and API (step 2): supabase_flutter.

## Layout
`application/lib/core` holds what every feature uses: theme, routing, sync, shared widgets.
`application/lib/features/<name>` holds one section each. Inside a feature, add `data/` (repositories, API calls), `domain/` (plain models) and `presentation/` (screens, widgets, providers) as the feature needs them.
A feature never imports another feature's `presentation/`. Shared pieces move to `core/`.

## Rules
1. **No progression logic in Flutter.** The backend calculates recommendations (double progression). The app caches and displays them. With no cached recommendation it shows previous performance and planned targets.
2. **One write path.** Every change goes into the local outbox and is sent through `api_apply_operations`. Pull uses `api_pull_changes` with `next_rev`. Contract: `shared/api_contracts/`.
3. **Sync code stays in `core/sync`.** Features read the sync state and write through repositories. They never call Supabase directly.
4. **Local first.** Screens read from the local database. Network results land in the local database first.
5. **Units.** The database stores kg, cm, m, s. Convert only when displaying, using the user's unit settings.
6. **Dates.** Events carry `occurred_at`, `local_date` and `tz_offset_minutes`, as in `docs/TECHNICAL_CONTRACT.md`.
7. **Wording.** Observations and suggestions, never diagnosis or medical advice.
8. **Styling lives in `core/theme` and `core/widgets`.** Feature code reads colours with `context.pal` and builds screens from `AppCard`, `TitledCard`, `PillTabs`, `AppButton`, `MeterBar` and the chart widgets. Anything not backed by real data yet carries the `sample: true` badge in its `SectionHeader`; remove the flag when the data source is wired.

## Sign-in and device flow (step 2)
- One owner account in Supabase Auth, no registration (D3). The session is saved by supabase_flutter and restored at start.
- `SessionController` is the single state machine: `checking`, `signedOut`, `connecting`, `ready`, `revoked`. The router redirects from it.
- First sign-in calls `api_claim_owner` and `api_register_device`. After that the app opens `ready` from local facts alone, so it starts offline.
- Server calls go through `BackendGateway`. Errors arrive as `BackendError` with the contract code. The server puts the code as a message prefix (`device_revoked: ...`), and `BackendError.fromRaw` reads it.
- When the sync client (step 3) receives `device_revoked`, it calls `SessionController.markRevoked()`.
- Build settings come from `--dart-define-from-file`. A service-role key in `SUPABASE_ANON_KEY` stops the app at start.

## Layout change from the original plan
The plan named the app folder `mobile_web/`. The owner chose `application/` (decision F12). Update the layout block in the root `README.md` accordingly.

## Design pass (step 3)
- Designs are dark first (default theme mode), with a light palette derived from the same tokens. Settings changes the mode.
- The Home header shows the sync pill; Settings shows the full sync status (the other tabs follow the designs and have no pill).
- The workout session is a full-screen route (`AppRoutes.session`) outside the bottom bar.


## Local database and sync (step 4)

- `core/db/entities.dart`: the 56 synced tables and whether each is append-only, editable or versioned. Four are read-only on the phone.
- `core/db/local_store.dart`: the `LocalStore` interface. `sqflite_local_store.dart` is the SQLite version. `records` holds one JSON row per (entity, id) with the last server copy beside the local copy; `outbox` holds queued changes; `sync_state` holds the pull cursor and last sync time.
- `core/sync/change_writer.dart`: the only way features write. It stores the change, queues it, then starts a sync.
- `core/sync/sync_engine.dart`: one round = push queued operations in batches of 100 through `api_apply_operations`, then pull `api_pull_changes` in pages of 200 until `has_more` is false.
- Results: `applied` and `duplicate` clear the operation; `conflict` and `rejected` keep it as an issue and restore the server copy; `reference_missing` is retried up to 5 times. An unsent local edit is never overwritten by a pull.
- `core/sync/sync_runner.dart` (in `main.dart` only) starts a round when the app becomes ready, every 60 s and on resume.
- Screens reload when `dataRevisionProvider` changes.
- Still to do: screens read real data from `LocalStore` (steps 5 to 9); cache of the online-only Stage 4 functions (next targets, readiness, briefing).
