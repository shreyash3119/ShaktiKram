"""Shared test setup. The tests read a database that already holds backend/tests/sample_data.sql (run.sh prepares it)."""
import os
import shutil
import subprocess
import uuid
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
SOURCE_DB = os.environ.get("PFS_TEST_DB", "pfs_test")
READER_URL = os.environ.get("PFS_TEST_READER_URL", f"postgresql+psycopg://pfs_reader:pfs_reader_test@127.0.0.1:5432/{SOURCE_DB}")
os.environ["DATABASE_URL"] = READER_URL          # must be set before the app is imported

from sqlalchemy import create_engine, text  # noqa: E402


def admin_connect(dbname="postgres"):
    """A connection that may write. Uses the usual PG* environment variables (PGHOST, PGPORT, PGUSER, PGPASSWORD)."""
    import psycopg
    return psycopg.connect(dbname=dbname, autocommit=True)


def fingerprints(dbname):
    with admin_connect(dbname) as c:
        c.execute("set time zone 'UTC'")
        return {r[0]: (r[1], r[2]) for r in c.execute("select table_name, row_count, fingerprint from pfs_table_fingerprints()")}


@pytest.fixture(scope="session")
def engine():
    eng = create_engine(READER_URL)

    try:
        with eng.connect() as c:
            n = c.execute(
                text("select count(*) from workout_sessions")
            ).scalar()

    except Exception as exc:  # noqa: BLE001
        eng.dispose()
        pytest.fail(
            f"Stage 5 test database is not reachable as pfs_reader: {exc}",
            pytrace=False,
        )

    if n is None or n < 20:
        eng.dispose()
        pytest.fail(
            "Stage 5 sample data is missing or incomplete. "
            "Run backend/tests/sample_data.sql first.",
            pytrace=False,
        )

    return eng


@pytest.fixture
def conn(engine):
    with engine.connect() as c:
        yield c


@pytest.fixture
def scratch_db():
    """An empty, freshly migrated database, removed afterwards."""

    psql = shutil.which("psql")

    if not psql:
        pytest.fail(
            "psql is required to build the Stage 5 restore-test database.",
            pytrace=False,
        )

    name = "pfs_restore_" + uuid.uuid4().hex[:8]

    try:
        with admin_connect() as c:
            c.execute(f'create database "{name}"')

    except Exception as exc:  # noqa: BLE001
        pytest.fail(
            f"Could not create Stage 5 scratch database {name}: {exc}",
            pytrace=False,
        )

    def run(path):
        subprocess.run(
            [
                psql,
                "-v",
                "ON_ERROR_STOP=1",
                "-q",
                "-d",
                name,
                "-f",
                str(path),
            ],
            check=True,
            capture_output=True,
            text=True,
        )

    try:
        run(ROOT / "backend" / "tests" / "supabase_stub.sql")

        for migration in sorted(
            (ROOT / "backend" / "supabase" / "migrations").glob("*.sql")
        ):
            run(migration)

        yield name

    finally:
        with admin_connect() as c:
            c.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')