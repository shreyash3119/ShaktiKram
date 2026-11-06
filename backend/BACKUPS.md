# Backups and restore

Three layers. Use at least the first two.

1. **Managed backups (Supabase).** Turn on daily backups for the project (paid plans) and consider point-in-time recovery. Confirm in the dashboard that they are enabled; the free plan has none.
2. **Logical backups you control.** `DATABASE_URL=... backend/scripts/backup.sh [dir]` writes a compressed dump of the whole `public` schema (all tables, history, audit log, sequences). Schedule it (daily) and keep copies off the server. Take one before every production migration.
3. **Storage files.** The `media` bucket (reference videos, images) is NOT inside the database dump. Copy it separately (Storage API download, or the dashboard) until Stage 5 adds a full export that includes media.

## Verify a restore (do this monthly, and after changing migrations)

`backend/scripts/restore_verify.sh <database>` restores a fresh dump into a scratch database and compares row counts, a content hash per table and the highest revision. It also checks the revision sequence is ahead of the data. The test suite runs it on every run.

## Restoring for real

1. Create the new project/database and enable the `btree_gist` extension.
2. Restore the dump (`pg_restore --no-owner`, skipping the `public` schema creation, as `restore_verify.sh` does).
3. Re-create the owner user in Auth, sign in, and call `api_claim_owner()` (the old owner id belongs to the old project; clear `app_owner` first on the new database).
4. Register devices again. Copy the `media` bucket files back.
