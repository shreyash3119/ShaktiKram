# Flutter integration: Phase 2 (authentication and device lifecycle)

Branch `integration/phase2-auth-device`, on top of `integration/phase1-config-sync`. Nothing under `backend/` or `shared/` was changed.
Checked against `backend/supabase/migrations/20261106000200_devices_and_access.sql` (read only). No live Supabase run was possible here, so the live checks below are still for the owner to do.

## Audit result
| Flow | Backend behaviour | App behaviour |
|---|---|---|
| Fresh install | `api_claim_owner` then `api_register_device` | Same order. Both are safe to repeat |
| Returning install | none needed | Opens ready from stored facts without calling the server |
| Not the owner | `unauthorized: this app already has an owner` | Signed out with a clear message (existing test) |
| Device removed | `device_revoked` (PT403) from register, pull and push | Moves to the revoked screen. Nothing queued is lost |
| Token refresh | Supabase client | A failed refresh arrives as a sign-out event and returns to sign-in |

## Problems found and fixed
1. **A removed device could never be used again.** The revoked screen says "sign out, then sign in again", but the same device id was reused, and the server refuses a removed id for ever. Signing out of a removed device now makes a new device id, so the next sign-in registers a fresh device. Local data stays on the phone.
2. **The server not knowing this device** (`unauthorized: device is not registered`, for example after the server data was reset while the phone still said "registered") left sync failing for ever. Sync now registers the device again, without leaving the app, and retries once. If the server says the device is removed or the account is not the owner, the matching screen is shown.

## Tests added
`session_controller_test.dart` (new device id after removal, quiet re-registration, its failure paths), `sync_engine_test.dart` (unregistered device versus plain unauthorized), `sync_status_test.dart` (sync status, offline, revoked, re-registration, with the in-memory store and fake gateway). Not run here: run `flutter analyze` and `flutter test`.

## Still to check live (owner, development Supabase project)
1. Fresh install: sign in, then see one row in `devices`.
2. Kill and reopen the app offline: it opens without a server call.
3. In Manage devices, remove another phone and see it end in the revoked screen at its next sync.
4. Delete this phone's row in `devices` in the dashboard, then Sync now: the row comes back.
5. Backend note (B5): revoking a device does not end its Supabase Auth session (see `backend/README.md`). A removed phone cannot read or write data, but stays signed in until it syncs.
