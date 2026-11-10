# Flutter integration: Phase 3 (initial pull and SQLite persistence)

Branch `integration/phase3-initial-pull`, on top of Phase 2. Nothing under `backend/` or `shared/` was changed.

## What was already right (checked against `api_pull_changes` in `20261106000500_sync_core.sql`)
- All 56 synced tables have an `id` column, so every pulled row can be stored.
- Pull is by global `rev`; a row changed during paging simply shows up again later with a higher `rev`, and the store ignores rows older than what it holds.
- Each page and the cursor (`last_rev`) are written in one transaction, so a crash or lost connection leaves the cursor exactly after the last stored page.

## Added
1. **Versioned database migration (schema v2).** `core/db/schema.dart` holds one list of statements per version. Version 2 adds an `occurred_at` column and a `record_refs` table with indexes. A phone that already has a version 1 database is upgraded in place: new columns are filled from the records it already holds, and no record or queued change is touched.
2. **Indexed lookups for the feature screens** (so Phase 5 to 7 do not scan every record): `list` now orders and limits in SQL, and the new `listByRef(entity, field, id)` finds children by their link (`session_id`, `session_exercise_id`, `entity_id`, `template_version_id` and so on) with an index.
3. **Download progress.** The sync reports rows received per page; Settings shows "Downloaded N records" during the first sync.
4. **Tests.**
   - `test/support/store_contract.dart`: 14 rules every store must follow, run on the in-memory store (`flutter test`).
   - `integration_test/sqlite_store_test.dart`: the same rules on the real SQLite, plus reopen-after-close (the restart check) and an upgrade of a version 1 database. Run on a phone or emulator: `flutter test integration_test/sqlite_store_test.dart -d <device id>`.
   - `sync_engine_test.dart`: first download over several pages, interrupted halfway then continued, nothing-new pull.
5. The schema statements were also run through a real SQLite (3.x) here, including the upgrade of a populated version 1 database and the query plans (both lookups use their indexes). The Dart code itself has not been compiled or run.

## Known limits
- If the server's data is ever reset so that revisions restart lower, a phone with a higher saved cursor would pull nothing. The backend keeps revisions rising across restores (sequence jump after restore), so this is only a risk after a full manual database reset. A "download everything again" action in Settings can be added later; it is not in this phase.
- `api_pull_changes` returns every table's rows in one stream; the first sync of a large history takes several pages of 200 rows.

## Exit check (owner, development Supabase project)
1. Fresh install, sign in, wait for "Synced". Settings shows a record count above 0 (seed data: exercises, muscles and so on).
2. Close the app completely and reopen it with airplane mode on: the same count shows.
3. In the Supabase dashboard change a row (for example a goal title), tap Sync now: the count or value changes on the phone.
