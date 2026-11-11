# Flutter integration: Phase 4 (first complete write and sync round-trip)

Branch `integration/phase4-write-roundtrip`, on top of Phase 3. Nothing under `backend/` or `shared/` was changed.

## Added
1. **A fake server that follows the backend's rules** (`test/support/fake_server.dart`), written from `pfs_dispatch`, `pfs_apply_op` and `api_pull_changes` in `20261106000500_sync_core.sql`: global revisions, repeated `op_id` answers, the three record classes, the conflict rule (a different device wrote since `base_rev` and the server copy is at least as new), soft delete, `new_version`, device checks. It uses the app's real table registry. It is only as right as my reading of the SQL, so it is not a substitute for the live check below.
2. **Round-trip tests** (`test/write_roundtrip_test.dart`), all with the real `SyncEngine` and local store:
   - create, edit, delete, each coming back with a new revision;
   - create, edit and delete all done offline, then sent in order;
   - a lost response replayed without creating the record twice;
   - refused changes (missing field, read-only table, edit of an unknown record);
   - two phones: a change shows on the other phone, a conflict where the older change loses, a newer change from a stale phone that still wins, an append-only correction and a stale one that is not silently accepted, versioned records;
   - removed device, and a device the server forgot;
   - the whole app stack (`ChangeWriter`, sync status, session) through the live check logic.
3. **Live sync check** (`core/sync/sync_check.dart`, Settings card in debug builds only). Creates a meal called "SYNC CHECK <time>", syncs, edits it, syncs, deletes it (soft delete), syncs, reading the server's copy back after each step. It stops at the first failed step and says why.
4. `syncNow()` now returns a future that finishes when all queued sync work is done (it used to return at once when a sync was already running).

## Run the live check (owner)
Use a development Supabase project, not production: the check writes one meal row (it ends soft-deleted and stays in that table).
1. `flutter run --dart-define-from-file=dart_defines.json` in debug mode and sign in.
2. Settings, "Sync check (development)", tap "Run sync check".
3. Expected: five lines, all "Passed" (Save on the phone, Create on the server, Edit on the server, Delete on the server, Final state).
4. In the Supabase table editor, `meals` shows the row with `deleted_at` filled in and `device_id` equal to this phone's id.
5. Then try airplane mode: save a weight on Home, check Settings says "1 waiting", turn the network on, tap Sync now.
Send me the result of step 3 (or the failed line).

## Not done in this phase
- Conflict and refused-change messages are only in Settings (counts, "N changes were not accepted"). A screen to read and dismiss each issue comes with the feature screens.
- The tests have not been run (no Flutter SDK here). Run `flutter pub get`, `flutter analyze`, `flutter test`.
