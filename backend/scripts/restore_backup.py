#!/usr/bin/env python3
"""Restore a backup (.zip made by /api/v1/backup/export) into a clean, freshly migrated database.
Usage: python backend/scripts/restore_backup.py --database-url "postgresql://postgres:...@host:5432/postgres" backup.zip
Use a role that can write (never the read-only reporting role). Steps and checks: backend/BACKUPS.md."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "fastapi"))
from app.backup.restore import RestoreError, restore  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("backup", help="path to the backup .zip")
    ap.add_argument("--database-url", required=True)
    ap.add_argument("--force-schema", action="store_true", help="restore even if the database layout differs (not recommended)")
    ap.add_argument("--check-only", action="store_true", help="validate the file and the target database, write nothing")
    ap.add_argument("--yes", action="store_true", help="do not ask for confirmation")
    a = ap.parse_args()
    try:
        blob = Path(a.backup).read_bytes()
    except OSError as e:
        sys.exit(f"cannot read the backup file: {e}")
    if not a.check_only and not a.yes and input("This writes into the target database. Type RESTORE to continue: ").strip() != "RESTORE":
        sys.exit("cancelled")
    try:
        result = restore(a.database_url, blob, force_schema=a.force_schema, check_only=a.check_only)
    except RestoreError as e:
        sys.exit(f"RESTORE FAILED: {e}")
    if result["checked"]:
        print(f"check passed: the backup file is intact and the target database is clean and has the same layout ({result['tables']} tables). Nothing was written.")
        return
    print(f"restore verified: {result['tables']} tables checked (row counts and content hashes match). Backup made {result['exported_at']}.")
    if not result["media_included"]:
        print("Media files were not part of this backup: copy the media bucket back separately.")
    print("Next: sign in as the owner and call api_claim_owner() (clear app_owner first on a new project), then register your devices again.")


if __name__ == "__main__":
    main()
