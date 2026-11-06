#!/usr/bin/env bash
# Logical backup of the public schema (all tables, history and audit log).
# Usage: DATABASE_URL=postgres://... backend/scripts/backup.sh [output_dir]
# Storage files (media) are NOT in this dump: back them up separately (see backend/BACKUPS.md).
set -euo pipefail
OUT="${1:-backups}"; mkdir -p "$OUT"
FILE="$OUT/pfs_$(date -u +%Y%m%dT%H%M%SZ).dump"
pg_dump -Fc --no-owner --schema=public "${DATABASE_URL:?set DATABASE_URL}" -f "$FILE"
echo "$FILE"
