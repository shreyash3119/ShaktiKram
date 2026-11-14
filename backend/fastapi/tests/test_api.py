import io
import uuid
import zipfile

import pytest
from fastapi.testclient import TestClient
from openpyxl import load_workbook
from sqlalchemy import text

from app.core.auth import Owner, require_owner
from app.main import app
from conftest import SOURCE_DB, admin_connect

SEP = "period=monthly&year=2026&month=9"
client = TestClient(app)


@pytest.fixture
def as_owner(engine):
    app.dependency_overrides[require_owner] = lambda: Owner(user_id="test-owner", token="test-token")
    yield
    app.dependency_overrides.clear()


@pytest.fixture
def owner_row(engine):
    uid = str(uuid.uuid4())
    with admin_connect(SOURCE_DB) as c:
        if c.execute("select count(*) from app_owner").fetchone()[0]:
            pytest.skip("the test database already has an owner")
        c.execute("insert into app_owner (auth_user_id) values (%s)", (uid,))
    yield uid
    with admin_connect(SOURCE_DB) as c:
        c.execute("delete from app_owner where auth_user_id = %s", (uid,))


def test_no_token_is_refused(engine):
    for url in (f"/api/v1/reports/summary?{SEP}", f"/api/v1/reports/export?{SEP}", "/api/v1/backup/export"):
        assert client.get(url).status_code == 401
    assert client.post("/api/v1/backup/validate", files={"file": ("b.zip", b"x")}).status_code == 401


def test_a_valid_account_that_is_not_the_owner_is_refused(engine, monkeypatch):
    async def fake(token):
        return str(uuid.uuid4())
    monkeypatch.setattr("app.core.auth.verify_token", fake)
    r = client.get(f"/api/v1/reports/summary?{SEP}", headers={"Authorization": "Bearer anything"})
    assert r.status_code == 403


def test_the_owner_is_let_in(owner_row, monkeypatch):
    async def fake(token):
        return owner_row
    monkeypatch.setattr("app.core.auth.verify_token", fake)
    r = client.get(f"/api/v1/reports/summary?{SEP}", headers={"Authorization": "Bearer anything"})
    assert r.status_code == 200 and r.json()["period"]["label"] == "September 2026"


def test_summary_and_period_list(as_owner):
    r = client.get(f"/api/v1/reports/summary?{SEP}&compare=true")
    assert r.status_code == 200
    body = r.json()
    assert body["training"]["attendance"]["consistency_pct"] == 90.0 and body["comparison"]["previous_period"]["label"] == "August 2026"
    assert "complete" in client.get("/api/v1/reports/periods").json()["periods"]
    assert client.get("/api/v1/reports/summary?period=complete").json()["period"]["label"] == "Complete history"
    assert client.get("/api/v1/reports/summary?period=daily&day=2026-09-02").json()["period"]["label"] == "2026-09-02"


@pytest.mark.parametrize("query", ["period=monthly&year=2026&month=13", "period=monthly&year=2026", "period=custom",
                                   "period=custom&date_from=2026-09-02&date_to=2026-09-01", "period=fortnightly", "period=yearly&year=abc"])
def test_invalid_period_inputs_are_rejected(as_owner, query):
    assert client.get(f"/api/v1/reports/summary?{query}").status_code == 422


def test_exports_have_the_right_type_and_name(as_owner):
    x = client.get(f"/api/v1/reports/export?{SEP}&format=xlsx")
    assert x.status_code == 200 and "spreadsheetml" in x.headers["content-type"]
    assert 'filename="fitness-report-september-2026.xlsx"' in x.headers["content-disposition"]
    assert "Workout sessions" in load_workbook(io.BytesIO(x.content)).sheetnames
    p = client.get(f"/api/v1/reports/export?{SEP}&format=pdf")
    assert p.status_code == 200 and p.headers["content-type"] == "application/pdf" and p.content.startswith(b"%PDF")
    assert client.get(f"/api/v1/reports/export?{SEP}&format=docx").status_code == 422


def test_backup_endpoints(as_owner):
    b = client.get("/api/v1/backup/export")
    assert b.status_code == 200 and "manifest.json" in zipfile.ZipFile(io.BytesIO(b.content)).namelist()
    ok = client.post("/api/v1/backup/validate", files={"file": ("backup.zip", b.content)}).json()
    assert ok["ok"] is True and ok["counts"]["sets"] > 0
    bad = client.post("/api/v1/backup/validate", files={"file": ("backup.zip", b"not a backup")})
    assert bad.status_code == 200 and bad.json()["ok"] is False
    c = client.get("/api/v1/backup/export?format=csv")
    assert c.status_code == 200 and "sets.csv" in zipfile.ZipFile(io.BytesIO(c.content)).namelist()


def test_the_reporting_role_cannot_write(engine):
    with engine.connect() as conn:
        assert conn.execute(text("show default_transaction_read_only")).scalar() == "on"
    for sql in ("insert into goals (type, title) values ('strength', 'x')", "update settings set time_zone = 'UTC'", "delete from goals",
                "truncate audit_log", "select api_apply_operations(gen_random_uuid(), gen_random_uuid(), '[]')"):
        with engine.connect() as conn:
            with pytest.raises(Exception, match="permission denied|read-only"):
                conn.execute(text(sql))
