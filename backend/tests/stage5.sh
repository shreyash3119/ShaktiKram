#!/usr/bin/env bash
# Stage 5 steps of the test run: sample data, the reporting role's test password, and the reporting service tests (pytest).
# Called by run.sh after the SQL tests: bash backend/tests/stage5.sh "$DB"
# Uses the same PG* environment variables as run.sh (PGHOST, PGPORT, PGUSER, PGPASSWORD).
set -euo pipefail
cd "$(dirname "$0")/../.."
DB="${1:-${PFS_TEST_DB:-pfs_test}}"
if [[ ! "$DB" =~ ^pfs_test[A-Za-z0-9_]*$ ]]; then
  echo "Refusing to run: the database name must be a safe scratch database name starting with pfs_test."
  exit 1
fi
# Refuse to run against a hosted Supabase database.
case "${PGHOST:-}" in
  *supabase.co*|*supabase.com*)
    echo "Refusing to run Stage 5 tests against a hosted Supabase host."
    exit 1
    ;;
esac

PY="$(command -v python)"
P="psql -v ON_ERROR_STOP=1 -q"

$P -d "$DB" -f backend/tests/sample_data.sql
$P -d postgres -c "alter role pfs_reader login password 'pfs_reader_test'"

echo "Checking Stage 5 test dependencies..."

if ! "$PY" -c "import pytest, fastapi, openpyxl, reportlab, matplotlib, psycopg, sqlalchemy, pypdf, httpx"; then
  echo "ERROR: Stage 5 test dependencies are missing."
  echo "Install them using:"
  echo "  pip install -r backend/fastapi/requirements-dev.txt"
  exit 1
fi

echo "Running Stage 5 reporting service tests..."

(
  cd backend/fastapi
  PFS_TEST_DB="$DB" \
  PFS_TEST_READER_URL="postgresql+psycopg://pfs_reader:pfs_reader_test@${PGHOST:-127.0.0.1}:${PGPORT:-55432}/$DB" \
  "$PY" -m pytest -q
)
