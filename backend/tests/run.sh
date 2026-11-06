#!/usr/bin/env bash
# Builds a scratch PostgreSQL database from the migrations and runs every test.
# Needs: psql, pg_dump, pg_restore, python3, and a role allowed to create databases/roles (local dev only).
set -euo pipefail
cd "$(dirname "$0")/../.."
DB="${PFS_TEST_DB:-pfs_test}"
P="psql -v ON_ERROR_STOP=1 -q"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB"
$P -d "$DB" -f backend/tests/supabase_stub.sql
for f in backend/supabase/migrations/*.sql; do echo "migrate $(basename "$f")"; $P -d "$DB" -f "$f"; done
$P -d "$DB" -f backend/supabase/seed.sql
$P -d "$DB" -f backend/tests/helpers.sql
python3 shared/vocabulary/validate.py
python3 backend/tests/check_vocabulary_sync.py "$DB"
for t in backend/tests/*.test.sql; do echo "== $(basename "$t")"; $P -d "$DB" -f "$t"; done
bash backend/scripts/restore_verify.sh "$DB" backend/tests/supabase_stub.sql
echo "ALL STAGE 1 TESTS PASSED"
