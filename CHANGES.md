# Stage 2 changes: how to apply

Unzip over your repository root (it only contains new and changed files), then:

1. Before unzipping, keep your full dependency list: `git mv backend/fastapi/requirements.txt backend/fastapi/requirements-lock.txt`
   (the zip brings a new `requirements.txt` with direct dependencies only).
2. Do NOT expect `backend/supabase/config.toml` in this zip: your version (port 54325, email provider on) is correct and unchanged.
3. `git status` should show the files listed below. Run `bash backend/tests/run.sh` (it now refuses to run against a hosted host
   or a database whose name does not start with `pfs_test`).
4. Local Supabase: `cd backend && supabase db reset` applies the 11 new migrations to your local database.
5. Hosted project: `supabase db push` applies the same migrations. Take a backup first (`backend/scripts/backup.sh`).

## What is new
- Migrations `20261107000050` to `20261107000700` (hardening, then exercises, templates, splits, schedule and breaks, sessions, views)
- Tests `60`, `70`, `80`; `shared/api_contracts/stage2_entities.md`; `backend/scripts/smoke_rest.sh`
- Decisions D18 to D23, contract section 15, Stage 2 status

## What was corrected from Stage 1
- Default function privileges (PUBLIC kept execute on new functions) and `btree_gist` out of the public schema
- `run.sh` safety guard and portable Python lookup
- FastAPI: `DEBUG` defaults to off, docs disabled in production, direct dependencies only
- Docs now explain why the email provider stays on locally
