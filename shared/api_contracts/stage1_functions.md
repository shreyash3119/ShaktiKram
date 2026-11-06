# Stage 1 API functions

Called as Supabase RPC (`POST /rest/v1/rpc/<name>`) with the owner's session token. Success responses use the envelope in
`docs/TECHNICAL_CONTRACT.md` section 9: `{ "data": ..., "meta": { request_id, server_time, schema_version, next_cursor } }`.
Function-level errors use the codes in `error_codes.json` (HTTP 401 unauthorized, 403 device_revoked, 404 not_found, 413 payload_too_large, 422 validation_failed).

| Function | Arguments | Returns (`data`) | Notes |
| --- | --- | --- | --- |
| `api_claim_owner()` | none | `{ owner: true }` | First signed-in caller only. Otherwise `unauthorized`. |
| `api_register_device(p_device_id, p_label, p_platform)` | uuid, text, `mobile` or `web` | the device row | Idempotent. A revoked device gets `device_revoked`. |
| `api_list_devices()` | none | array of device rows | |
| `api_revoke_device(p_device_id)` | uuid | the device row with `revoked_at` | `not_found` if unknown. |
| `api_apply_operations(p_device_id, p_request_id, p_operations)` | uuid, uuid, jsonb array (max 500) | `{ results: [ { op_id, result, rev?, error_code?, message?, original_result? } ] }` | `result` is `applied`, `duplicate`, `rejected` or `conflict`. |
| `api_pull_changes(p_device_id, p_since_rev = 0, p_limit = 200)` | uuid, bigint, int (1 to 500) | `{ rows: [ { entity, rev, record } ], next_rev, has_more }` | Includes soft-deleted rows. Use `next_rev` as the next `since_rev`. |

## Operation (element of `p_operations`)

| Field | Required | Meaning |
| --- | --- | --- |
| `op_id` | yes | uuid. A replay returns `duplicate` and changes nothing. |
| `seq` | yes | Order within the request. |
| `entity` | yes | Table name. Must be writable (not `goal_status_events`, `audit_log`, etc.). |
| `action` | yes | `upsert`, `delete` (soft) or `new_version` (versioned tables only). |
| `record_id` | for upsert and delete | The row id (made by the client). |
| `base_rev` | for edits | The `rev` the client last saw. Without it an upsert of an existing id is ignored. |
| `client_updated_at` | optional | Used only to settle conflicts. Clamped to server time plus 5 minutes. |
| `reason` | optional | Stored in `audit_log`. |
| `payload` | for upsert and new_version | Column values. `rev`, `created_at`, `updated_at`, `device_id`, `deleted_at` are refused. A `new_version` payload needs `entity_id` and may set `effective_from`. |

## Tables writable in Stage 1

`profile_versions` (new_version only), `settings` (edit the one existing row), `goals`, `reminder_rules`, `muscles`, `body_regions`, `equipment`, `exercises`.
Seeded rows of `muscles`, `body_regions` and `equipment` cannot be changed, except `equipment.is_available_at_gym`. Rows created through the API are always custom.
`goal_status_events` is written by the database when a goal's status changes and is read-only for clients.
