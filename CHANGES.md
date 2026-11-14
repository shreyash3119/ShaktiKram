# Stage 5 changes: how to apply

Unzip over your repository root (it only contains new and changed files), then:

1. **Add one line to `backend/tests/run.sh`**, just before the `restore_verify.sh` line: `bash backend/tests/stage5.sh "$DB"`.
   This zip does not contain `run.sh`, so your local changes to it (ports, Windows fixes) are not overwritten.
2. `backend/fastapi/requirements.txt` changed (Excel, PDF and chart libraries added; `pytest` moved to `requirements-dev.txt`). Run `pip install -r backend/fastapi/requirements-dev.txt`.
3. Local database: apply the new migration `20261110000100_report_reader` using the project's established migration workflow. Do not use `supabase db reset` on an existing database, as it can reset database contents. Hosted project: take a backup, then apply pending migrations with `supabase db push`.
4. Set a password for the reporting role: `alter role pfs_reader login password '...'`. Copy `backend/fastapi/.env.example` to `.env` and fill it in (use the `pfs_reader` connection).

## What is new
- Migration `20261110000100_report_reader.sql` and test `97_stage5_reader.test.sql`
- Reporting service: `app/reports/` (periods, summary, Excel, PDF, charts), `app/backup/` (export, validate, restore), `app/core/auth.py`, `app/core/vocabulary.py`, routes `reports.py` and `backup.py`
- `backend/scripts/restore_backup.py` (command line), `backend/tests/stage5.sh`, `backend/tests/sample_data.sql`
- Tests in `backend/fastapi/tests/` (periods, summary, exports, backup and restore, API, read-only role)
- `BACKUPS.md`, `.env.example`, `shared/api_contracts/stage5_reports_backup.md`, decisions D38 to D45, contract section 18, Stage 5 status
- `statuses.json`: `report_period` now includes `daily` and `weekly`

## Not yet run (manual testing pending)
Nothing in Stage 5 has been run by the automated tests, and the restore script has never been executed. See the list in the Stage 5 section of `docs/BACKEND_STAGES.md`.
