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
2. In the Supabase dashboard (Authentication, Users), create the one owner user. In `config.toml`, `[auth] enable_signup = false` blocks all sign-ups while `[auth.email] enable_signup = true` keeps the email provider on, which password sign-in needs. On the hosted project switch off "Allow new users to sign up" and keep the Email provider enabled. Create the owner before anyone else could: the first signed-in user to call `api_claim_owner()` becomes the owner.
3. Sign in on the first device and call `api_claim_owner()` once. It succeeds only for the first caller.
4. On each device: sign in once, generate a device UUID, and call `api_register_device(device_id, label, platform)`.
5. Lost device: call `api_revoke_device(device_id)`, then sign out all sessions in the dashboard and change the owner password.

Never put the service-role key or the database password in the mobile app.

## Backups

See `BACKUPS.md`.

## Reporting service (FastAPI)

Reports, Excel and PDF export and the full backup are served by `backend/fastapi`. It reads the database as the read-only role `pfs_reader` and never writes.

1. Apply the migrations (they create the role without a password), then set one: `alter role pfs_reader login password '...';`
2. `cd backend/fastapi`, create a virtual environment, `pip install -r requirements.txt`, copy `.env.example` to `.env` and fill it in (use the `pfs_reader` connection, never the owner one).
3. Start it: `uvicorn app.main:app --reload`. The app calls `/api/v1/reports/...` and `/api/v1/backup/...` with the owner's access token. Interactive docs are at `/docs` (development only).
4. Tests: `pip install -r requirements-dev.txt`, then `bash backend/tests/run.sh` (it loads the sample data and runs `backend/tests/stage5.sh`).

Restoring a backup is a command-line operation, see `BACKUPS.md`.
