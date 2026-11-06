# Decision Register

Where the earlier planning documents disagreed, this register records the resolution.
Items marked **Proposed** are being built to by default and can be changed.

| # | Topic | Architecture v2 | Development Plan | Resolution | Status |
| --- | --- | --- | --- | --- | --- |
| D1 | Backend platform | Supabase or custom | Supabase, optional FastAPI | Supabase + PostgreSQL; FastAPI only for reports/exports/heavy calculations | Proposed |
| D2 | Web capability | Read-only monitoring | Full editing, same as mobile | **On hold.** Decide after the Flutter app exists. The backend works for either choice, because every write goes through `api_apply_operations` | Deferred (owner decision, 5 Nov 2026) |
| D3 | Login | Login + biometric | No login screens | One owner account in Supabase Auth, sign-ups disabled. Each device signs in once and the session persists, so there is no daily login. RLS allows only that owner. Each device is also registered in `devices` and can be revoked (see section 8 of the contract). Custom device tokens were rejected: hand-made token signing is easy to get wrong | Agreed (owner decision, 5 Nov 2026) |
| D4 | user_id columns | On every table | Removed | Removed (single user) | Proposed |
| D5 | Offline | Mobile offline-first | Mobile offline-first; web online only | Mobile offline-first; web online editing | Agreed |
| D6 | Report periods | Monthly/yearly | Monthly, quarterly, half-yearly, yearly, custom, complete | Use the wider list | Agreed |
| D7 | Business logic location | Shared test vectors, phone + server | Avoid duplicate logic across layers | One written spec per rule in shared/calculation_specs; phone implements only what it needs offline; server is authoritative; both pass shared test vectors | Proposed |

| D8 | Write interface | Sync endpoints | Same operations on mobile and web | One function, `api_apply_operations`, used by phone sync and web edits | Proposed |
| D9 | Private access mechanism | Login | "Secure private API gateway or device access" | One-time device pairing issues a revocable token stored in `devices`. A single secret shared by all clients was rejected because it cannot be revoked per device and would sit inside the web app. Exact mechanism confirmed in Stage 1 | Proposed |
| D10 | Reminders | `reminder_rules` table | Notifications as a system service | Backend stores rules and answers "what is due"; delivery is local scheduled notifications on the device | Proposed |
| D11 | Export and backup owner | B (suggested) | C | C owns reports, export, backup and restore; B owns reminders | Proposed |
| D12 | Scales left open by the spec | n/a | n/a | Check-in fields 1 to 5 with a machine-readable direction per field; injury severity mild/moderate/severe; personal difficulty 1 to 5; muscle development categories: one per level (1 high priority, 2 needs improvement, 3 average, 4 above average, 5 well developed), matching the spec examples | Agreed (categories), Proposed (rest) |
| D13 | Write ordering | n/a | n/a | `api_apply_operations` takes one database-wide lock per request. Revisions therefore become visible in order and a pull can never skip a row | Done in Stage 1 |
| D14 | Restore vs triggers | n/a | n/a | Restore mode (`pfs.restore_mode`) keeps ids, revs and timestamps. Only server-side roles can use it, the API forces it off, and `pfs_restore_finish()` moves the revision sequence past the restored data | Done in Stage 1 |
| D15 | Audit device and reason | n/a | n/a | The API stamps the transaction with `pfs.device_id` and `pfs.reason`; triggers copy them into `audit_log`. Updates store changed columns only | Done in Stage 1 |
| D16 | Conflict rule | n/a | later `client_updated_at` wins | A conflict needs a different device to have written the row since `base_rev`. A device's own earlier edits never conflict (found by a Stage 1 test: queued edits from one phone would otherwise reject each other) | Done in Stage 1 |
| D17 | Sync core timing | n/a | Sync is Stage 6 | The write function, `devices`, `sync_operations` and pull by revision moved into Stage 1. Stage 6 is client offline behaviour and its tests | Done in Stage 1 |

## Consequences of D2 and D3

- The web client is not designed yet. When it is, it signs in with the same owner account. If it is read-only, the API can reject its writes by device platform; if it edits, it uses the same operations as the phone.
- Authentication is Supabase Auth, so there are no hand-made tokens. Token lifetime is one hour with refresh-token rotation.
- Revoking a device blocks its writes and pulls at once. Its REST reads stay possible until its access token expires (up to one hour), because RLS cannot tell devices apart. For a lost phone: revoke the device, then sign out all sessions and change the password.
- Two clients writing at once only matters if the web client edits. The conflict rules already cover it.

## Explicitly out of scope

- Progress photos and visual comparison (postponed by the user)
- Multi-user accounts, registration, roles
- Backend code before the contract is approved
