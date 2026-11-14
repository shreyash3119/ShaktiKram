import io
import json
import zipfile

import pytest
from sqlalchemy import text

from app.backup.export import build_backup, build_csv_export, collect_media
from app.backup.restore import RestoreError, restore
from app.backup.validate import validate_backup
from conftest import SOURCE_DB, admin_connect, fingerprints


def _rebuild(blob, changes):
    src = zipfile.ZipFile(io.BytesIO(blob))
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w") as z:
        for n in src.namelist():
            z.writestr(n, changes.get(n, src.read(n)))
    return out.getvalue()
def _rebuild_with_additions(blob, changes, additions):
    src = zipfile.ZipFile(io.BytesIO(blob))
    out = io.BytesIO()

    with zipfile.ZipFile(out, "w") as z:
        for name in src.namelist():
            z.writestr(name, changes.get(name, src.read(name)))

        for name, content in additions.items():
            z.writestr(name, content)

    return out.getvalue()


@pytest.fixture(scope="module")
def blob(engine):
    return build_backup(engine)


def test_backup_is_valid_and_counts_match_the_database(engine, blob, conn):
    v = validate_backup(blob)
    assert v["ok"], v["errors"]
    assert v["counts"]["sets"] == conn.execute(text("select count(*) from sets")).scalar()
    assert "audit_log" in v["counts"] and v["manifest"]["media_included"] is False
    assert all(isinstance(t, str) for t in v["data"].values())      # each table is kept as PostgreSQL's own JSON text


def test_tampered_data_is_detected(blob):
    raw = zipfile.ZipFile(io.BytesIO(blob)).read("data.json")
    bad = raw.replace(b"Barbell bench press", b"Barbell bench pressX", 1)
    assert bad != raw
    v = validate_backup(_rebuild(blob, {"data.json": bad}))
    assert not v["ok"] and any("hash" in e for e in v["errors"])


def test_tampered_counts_are_detected(blob):
    m = json.loads(zipfile.ZipFile(io.BytesIO(blob)).read("manifest.json"))
    m["tables"]["sets"]["rows"] += 1
    v = validate_backup(_rebuild(blob, {"manifest.json": json.dumps(m).encode()}))
    assert not v["ok"] and any("sets" in e for e in v["errors"])


def test_invalid_files_are_refused():
    assert not validate_backup(b"this is not a zip")["ok"]
    empty = io.BytesIO()
    zipfile.ZipFile(empty, "w").close()
    assert not validate_backup(empty.getvalue())["ok"]


def test_a_backup_from_another_app_is_refused(blob):
    m = json.loads(zipfile.ZipFile(io.BytesIO(blob)).read("manifest.json"))
    m["app"] = "something-else"
    assert not validate_backup(_rebuild(blob, {"manifest.json": json.dumps(m).encode()}))["ok"]


def test_media_collection_records_failures_and_unsafe_names():
    def fetch(ref):
        if ref == "broken.mp4":
            raise RuntimeError("storage said no")
        return b"file-bytes"
    files, entries = collect_media([{"file_ref": "a.jpg"}, {"file_ref": "broken.mp4"}, {"file_ref": "../secret"}], fetch)
    assert list(files) == ["media/a.jpg"] and entries[0]["size"] == len(b"file-bytes")
    assert "error" in entries[1] and entries[2]["error"] == "unsafe file name"


def test_csv_export_is_not_a_restorable_backup(engine, conn):
    z = zipfile.ZipFile(io.BytesIO(build_csv_export(engine)))
    assert "sets.csv" in z.namelist() and "README.txt" in z.namelist()
    n = conn.execute(text("select count(*) from sets")).scalar()
    assert len(z.read("sets.csv").decode().splitlines()) >= n + 1
    assert not validate_backup(build_csv_export(engine))["ok"]


def test_restore_round_trip_matches_every_table(engine, blob, scratch_db):
    result = restore(f"dbname={scratch_db}", blob)
    assert result["tables"] > 40
    src, dst = fingerprints(SOURCE_DB), fingerprints(scratch_db)
    for t, v in src.items():
        if t != "audit_log":
            assert dst[t] == v, f"{t} differs after the restore"
    assert dst["audit_log"][0] == src["audit_log"][0] + 1          # the restore itself is logged
    max_rev = max(t["max_rev"] for t in validate_backup(blob)["manifest"]["tables"].values())
    with admin_connect(scratch_db) as c:
        assert c.execute("select action from audit_log order by at desc, rev desc limit 1").fetchone()[0] == "restore"
        assert c.execute("select nextval('pfs_global_rev')").fetchone()[0] > max_rev


def test_check_only_writes_nothing(blob, scratch_db):
    assert restore(f"dbname={scratch_db}", blob, check_only=True)["checked"] is True
    with admin_connect(scratch_db) as c:
        assert c.execute("select count(*) from sets").fetchone()[0] == 0


def test_restore_refuses_a_database_that_is_not_clean(blob):
    with pytest.raises(RestoreError, match="not clean"):
        restore(f"dbname={SOURCE_DB}", blob)


def test_restore_refuses_a_different_layout(blob, scratch_db):
    with admin_connect(scratch_db) as c:
        c.execute("alter table goals add column extra_column int")
    with pytest.raises(RestoreError, match="layout"):
        restore(f"dbname={scratch_db}", blob)


def test_restore_refuses_a_damaged_backup_before_touching_any_database(blob):
    raw = zipfile.ZipFile(io.BytesIO(blob)).read("data.json")
    damaged = _rebuild(blob, {"data.json": raw.replace(b"Barbell bench press", b"Barbell bench pressX", 1)})
    with pytest.raises(RestoreError, match="not valid"):
        restore("dbname=this_database_does_not_exist", damaged)

@pytest.mark.parametrize(
    "manifest_raw",
    [
        b"{invalid-json",
        b"[]",
        b"null",
    ],
)
def test_malformed_manifest_is_rejected(blob, manifest_raw):
    damaged = _rebuild(blob, {"manifest.json": manifest_raw})

    result = validate_backup(damaged)

    assert not result["ok"]
    assert result["data"] is None
    assert result["errors"]


def test_manifest_missing_required_fields_is_rejected(blob):
    manifest = json.loads(
        zipfile.ZipFile(io.BytesIO(blob)).read("manifest.json")
    )

    manifest.pop("tables")

    damaged = _rebuild(
        blob,
        {"manifest.json": json.dumps(manifest).encode()},
    )

    result = validate_backup(damaged)

    assert not result["ok"]
    assert any("tables" in error for error in result["errors"])


def test_invalid_data_json_is_rejected_even_when_hash_matches(blob):
    archive = zipfile.ZipFile(io.BytesIO(blob))
    manifest = json.loads(archive.read("manifest.json"))

    invalid_data = b"{invalid-json"
    manifest["data_sha256"] = __import__("hashlib").sha256(
        invalid_data
    ).hexdigest()

    damaged = _rebuild(
        blob,
        {
            "manifest.json": json.dumps(manifest).encode(),
            "data.json": invalid_data,
        },
    )

    result = validate_backup(damaged)

    assert not result["ok"]
    assert result["data"] is None


def test_partial_media_backup_is_validated_correctly(blob):
    archive = zipfile.ZipFile(io.BytesIO(blob))
    manifest = json.loads(archive.read("manifest.json"))

    media_content = b"sample-image-content"

    manifest["media_included"] = False
    manifest["media_status"] = "partial"
    manifest["media"] = [
        {
            "file_ref": "sample/image.jpg",
            "sha256": __import__("hashlib").sha256(
                media_content
            ).hexdigest(),
            "size": len(media_content),
        },
        {
            "file_ref": "sample/broken.mp4",
            "error": "storage download failed",
        },
    ]

    updated = _rebuild_with_additions(
        blob,
        {"manifest.json": json.dumps(manifest).encode()},
        {"media/sample/image.jpg": media_content},
    )

    result = validate_backup(updated)

    assert result["ok"], result["errors"]
    assert result["manifest"]["media_status"] == "partial"
    assert any("broken.mp4" in warning for warning in result["warnings"])


def test_partial_media_backup_rejects_missing_successful_file(blob):
    manifest = json.loads(
        zipfile.ZipFile(io.BytesIO(blob)).read("manifest.json")
    )

    manifest["media_included"] = False
    manifest["media_status"] = "partial"
    manifest["media"] = [
        {
            "file_ref": "sample/missing.jpg",
            "sha256": "0" * 64,
            "size": 10,
        },
        {
            "file_ref": "sample/broken.mp4",
            "error": "storage download failed",
        },
    ]

    damaged = _rebuild(
        blob,
        {"manifest.json": json.dumps(manifest).encode()},
    )

    result = validate_backup(damaged)

    assert not result["ok"]
    assert any("missing.jpg" in error for error in result["errors"])