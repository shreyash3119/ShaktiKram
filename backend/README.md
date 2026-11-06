# Backend

Supabase (PostgreSQL, Auth, Storage) is the primary platform. FastAPI is added only when a requirement needs Python
(report, PDF and Excel generation, heavy calculations). All conventions: `../docs/TECHNICAL_CONTRACT.md`.

- `supabase/migrations/` ordered SQL migrations (never edit a merged migration; add a new one)
- `supabase/seed.sql` fictional development data
- `supabase/config.toml` local and project settings (sign-ups disabled, one-hour access tokens, private buckets)
- `scripts/` `backup.sh`, `restore_verify.sh`
- `tests/` database tests; `tests/run.sh` runs everything

## Run the tests

Needs `psql`, `pg_dump`, `pg_restore`, Python 3 and a local PostgreSQL where your user may create databases and roles.
```
bash backend/tests/run.sh
```
The tests use plain PostgreSQL with small stand-ins for Supabase's `auth` and `storage` (`tests/supabase_stub.sql`).

## First-time setup of a Supabase project

1. Apply the migrations (`supabase db push`, or `supabase start` locally, which also runs `seed.sql`). Do not run `seed.sql` in production.
2. In the Supabase dashboard (Authentication, Users), create the one owner user. Sign-ups are disabled in `config.toml`; also turn them off in the hosted project's Auth settings.
3. Sign in on the first device and call `api_claim_owner()` once. It succeeds only for the first caller.
4. On each device: sign in once, generate a device UUID, and call `api_register_device(device_id, label, platform)`.
5. Lost device: call `api_revoke_device(device_id)`, then sign out all sessions in the dashboard and change the owner password.

Never put the service-role key or the database password in the mobile app.

## Backups

See `BACKUPS.md`.
