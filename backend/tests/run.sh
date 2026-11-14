
#!/usr/bin/env bash
# Builds a scratch PostgreSQL database from the migrations and runs every test.
# Needs: psql, pg_dump, pg_restore, python3, and a role allowed to create databases/roles (local dev only).

set -euo pipefail

# Local Supabase PostgreSQL connection
export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-55432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"

cd "$(dirname "$0")/../.."

DB="${PFS_TEST_DB:-pfs_test}"

# This script DROPS and recreates $DB. Refuse anything that is not clearly a scratch database or that points at a hosted project.
if [[ ! "$DB" =~ ^pfs_test[A-Za-z0-9_]*$ ]]; then
  echo "Refusing to run: PFS_TEST_DB must be a safe scratch database name starting with pfs_test."
  exit 1
fi

case "${PGHOST:-}" in
  *supabase.co*|*supabase.com*)
    echo "Refusing to run against a hosted Supabase host"
    exit 1
    ;;
esac

PY="$(command -v python)"

echo "Target server: host=${PGHOST:-local socket} port=${PGPORT:-default}; scratch database to recreate: $DB"

P="psql -v ON_ERROR_STOP=1 -q"

$P -d postgres -c "drop database if exists $DB" -c "create database $DB"

$P -d "$DB" -f backend/tests/supabase_stub.sql

for f in backend/supabase/migrations/*.sql; do
  echo "migrate $(basename "$f")"
  $P -d "$DB" -f "$f"
done

# Allow the local test runner to switch into the read-only reporting role.
$P -d "$DB" -c "GRANT pfs_reader TO $PGUSER WITH INHERIT FALSE, SET TRUE"

$P -d "$DB" -f backend/supabase/seed.sql
$P -d "$DB" -f backend/tests/helpers.sql

"$PY" shared/vocabulary/validate.py
"$PY" backend/tests/check_vocabulary_sync.py "$DB"
"$PY" backend/tests/run_vectors.py "$DB"

for t in backend/tests/*.test.sql; do
  echo "== $(basename "$t")"
  $P -d "$DB" -f "$t"
done

# Stage 5: reporting, exports, backup and restore tests
bash backend/tests/stage5.sh "$DB"

bash backend/scripts/restore_verify.sh "$DB" backend/tests/supabase_stub.sql

echo "ALL TESTS PASSED"
