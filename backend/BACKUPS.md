# Backups and restore

Three layers. Use at least the first two.

1. **Managed backups (Supabase).** Turn on daily backups for the project (paid plans) and consider point-in-time recovery. Confirm in the dashboard that they are enabled; the free plan has none.
2. **Backups you control.** Either of these, on a schedule, with copies kept off the server:
   - **The app's full backup**: `GET /api/v1/backup/export` (a zip). It holds every table, the history and the audit log, and its database contents can be restored by this project's script. Add `?include_media=true` to request media files in the archive. Some media downloads may fail; check the manifest and validation warnings.
   - **A database dump**: `DATABASE_URL=... backend/scripts/backup.sh [dir]`. Take one before every production migration.
3. **Storage files.** The `media` bucket (reference videos, images) is not inside a database dump. Use `include_media=true` on the full backup, or copy the bucket separately.

A **CSV export** (`GET /api/v1/backup/export?format=csv`) is for reading in a spreadsheet. It is **not a backup** and cannot be restored.

## What the full backup contains

A zip file:
- `manifest.json`: when it was made, a hash of the database layout, a row count and a content hash for every table, a hash of `data.json`, and the media list.
- `data.json`: every table as the exact JSON text PostgreSQL produces (so numbers keep their scale), taken in one consistent snapshot, in UTC.
- `media/...` only when requested.

Check a file without a database: `POST /api/v1/backup/validate` (upload the zip). It checks the format, the file hash, the row counts and the media hashes, and reports anything damaged or changed.

## Restoring for real

Restore is a command-line operation, never an API route: the reporting service cannot write. It needs a role that can write (for example `postgres`) and a **clean, freshly migrated database**.

1. Create the new project or database and apply all migrations (`supabase db push`). Do **not** run `seed.sql` or load sample data. The extension `btree_gist` must be available (the migrations create it).
2. Dry run (writes nothing): `python backend/scripts/restore_backup.py --check-only --database-url "<write-capable connection>" backup.zip`. It checks the file, that the database layout matches the backup, and that the target is clean.
3. Restore: the same command without `--check-only`. It asks you to type RESTORE (or pass `--yes`).
4. What it does, in one transaction: relaxes the foreign-key timing, clears the pre-filled reference rows, loads every table with the original ids, revisions and timestamps, checks the foreign keys, compares **row counts and a content hash for every table** with the backup, and only then keeps the result. Any mismatch keeps nothing. It also moves the revision counter past the restored data and records the restore in the audit log.
5. Sign in as the owner and call `api_claim_owner()` (on a new project clear `app_owner` first), then register your devices again.
6. Restore media files separately into the Supabase Storage `media` bucket. The restore script restores database contents only; it does not upload media files from the backup ZIP. If the ZIP contains media files, extract and upload the included files. If media was not included or some downloads failed, recover the missing files from the original storage backup or another copy.

It refuses to run when the file is damaged or from another app, when the database layout differs (apply the same migrations first), or when the target already holds data.

## Verify regularly (monthly, and after changing migrations)

- First validate the latest full backup using `POST /api/v1/backup/validate` or restore it into a scratch database with `--check-only`. Then perform an actual restore into a separate scratch database and open the app against it. `--check-only` validates the backup and target but does not restore data.
- `backend/scripts/restore_verify.sh <database>` restores a fresh `pg_dump` into a scratch database and compares per-table row counts, content hashes and the highest revision. The test suite runs it on every run.

## Known limits

- Media download uses the owner's own session against Supabase Storage. It has not been tried against a real project.
- Row counts and content hashes are compared in UTC; the scripts set this themselves.
