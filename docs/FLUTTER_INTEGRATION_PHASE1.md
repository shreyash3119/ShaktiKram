# Flutter integration: Phase 1 (configuration cleanup, contract audit, sync fixes)

Baseline: `main` at `1900ee0`. Branch: `integration/phase1-config-sync`. Nothing under `backend/` or `shared/` was changed.

## 1. Publishable key naming
Flutter-facing files now use `SUPABASE_PUBLISHABLE_KEY` / `publishableKey` / `supabasePublishableKey` / `checkPublishableKey`.
Fixed in this phase: `application/dart_defines.example.json`, `application/README.md`, `docs/FLUTTER_ARCHITECTURE.md`, leftover wording in `app_config.dart`.
`pubspec.yaml` now requires `supabase_flutter ^2.15.4`, a version whose `Supabase.initialize` has `publishableKey` (`anonKey` is deprecated there).
No `anonKey` or `ANON_KEY` text remains under `application/` or `docs/` (checked with a search).

Protected files that still use the old name (reported, not changed): `backend/scripts/smoke_rest.sh` (`SUPABASE_ANON_KEY` in the usage line and in the `apikey` header).

## 2. Contract audit (Flutter against the repo as it stands)
| Item | Result |
|---|---|
| `api_apply_operations` argument names (`p_device_id`, `p_request_id`, `p_operations`) and response (`data.results[]`) | Match |
| `api_pull_changes` argument names (`p_device_id`, `p_since_rev`, `p_limit`) and response (`rows`, `next_rev`, `has_more`) | Match |
| Operation fields sent (`op_id`, `seq`, `entity`, `action`, `record_id`, `base_rev`, `client_updated_at`, `reason`, `payload`) | Match; forbidden payload keys are stripped by `ChangeWriter` |
| `application/lib/core/db/entities.dart` against every `pfs_attach(...)` call in the migrations | 56 of 56 tables, record class and `client_writable` all match (4 read-only: `achievements`, `personal_records`, `goal_status_events`, `split_status_events`) |
| Error codes | Mapped from the `code:` message prefix, with PostgREST codes as fallback. The contract's JSON error envelope is still not what the server sends (known backend gap) |

## 3. Sync fixes
1. **A `duplicate` answer is no longer treated as success by itself.** Two kinds exist in the server code (`sync_core`):
   - a replay of a recorded `op_id` (has `original_result`): the first outcome counts, so only a first-time `applied` clears the change;
   - the record id already exists but the change did nothing (re-sent create, or an edit without `base_rev`): the change was not applied. It is kept as an issue with code `duplicate_ignored` and the server copy is restored.
2. **Create then edit of the same record.** Before, both could go in one request. The edit then had no `base_rev`, and the server ignores that as a re-sent create, so the edit was lost. Now each request carries at most one operation per record, and the next request is built after the first answer is stored, so the edit gets the revision the create received. An edit also waits while the create before it is waiting for a retry.
3. **Unreadable server answers** no longer escape the sync engine. They show as a sync problem and the changes stay queued.

Tests added in `application/test/sync_engine_test.dart` for each of these. They have not been run (no Flutter SDK in my environment); run `flutter analyze` and `flutter test`.

## 4. Backend requests / pending dependencies (not implemented, no workaround)
- B1. Error envelope: send `{error:{code,...}}` as the contract describes, instead of a message prefix.
- B2. `duplicate` without `original_result` cannot say why nothing changed. A `reason` field (`record_exists`, `missing_base_rev`, `base_rev_mismatch`) would let the app explain it.
- B3. `backend/scripts/smoke_rest.sh`: rename `SUPABASE_ANON_KEY` to the publishable-key name.
- B4. Stage 5 report, export and backup/restore contracts (needed for Phase 8).
