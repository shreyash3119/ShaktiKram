#!/usr/bin/env bash
# Restores a fresh dump of <source_db> into a scratch database and compares per-table row counts, content hashes and revisions.
# Usage: backend/scripts/restore_verify.sh <source_db> [prep.sql]   (prep.sql prepares a bare database, e.g. backend/tests/supabase_stub.sql)
set -euo pipefail
SRC="${1:?source database name}"; PREP="${2:-}"; SCRATCH="${SRC}_restore_check"; DUMP="$(mktemp)"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
trap 'rm -f "$DUMP" "$DUMP.list"; psql -q -d postgres -c "drop database if exists $SCRATCH" >/dev/null' EXIT
pg_dump -Fc --no-owner --schema=public "$SRC" -f "$DUMP"
psql -q -d postgres -c "drop database if exists $SCRATCH" -c "create database $SCRATCH"
[ -n "$PREP" ] && psql -v ON_ERROR_STOP=1 -q -d "$SCRATCH" -f "$PREP"
psql -q -d "$SCRATCH" -c "create extension if not exists btree_gist"   # prerequisite: extension used by the version-overlap constraint
pg_restore -l "$DUMP" | grep -vE ' SCHEMA - public| COMMENT - SCHEMA public| ACL - SCHEMA public' > "$DUMP.list"   # the target already has a public schema
pg_restore --no-owner --exit-on-error -L "$DUMP.list" -d "$SCRATCH" "$DUMP"
Q='select table_name, row_count, fingerprint, max_rev from pfs_table_fingerprints() order by 1'
psql -At -d "$SRC" -c "$Q" > "$DUMP.src"; psql -At -d "$SCRATCH" -c "$Q" > "$DUMP.dst"
if diff -u "$DUMP.src" "$DUMP.dst"; then echo "restore verified: $(wc -l < "$DUMP.src") tables identical"; else echo "RESTORE MISMATCH"; exit 1; fi
# The restored database must keep issuing new revisions above the old ones.
NEXT=$(psql -Atq -d "$SCRATCH" -c "select nextval('pfs_global_rev')"); MAXREV=$(awk -F'|' '{ if ($4>m) m=$4 } END { print m+0 }' "$DUMP.dst")
[ "$NEXT" -gt "$MAXREV" ] && echo "revision sequence ok ($NEXT > $MAXREV)" || { echo "sequence behind data"; exit 1; }
rm -f "$DUMP.src" "$DUMP.dst"
