"""Full-data backup and a spreadsheet-friendly CSV export. Read-only: one consistent snapshot of the whole database.
Each table is stored as the exact JSON text PostgreSQL produces, so numbers keep their original scale and the content hashes match after a restore.
Sessions are set to UTC because the hashes depend on the session time zone."""
import csv
import hashlib
import io
import json
import zipfile
from datetime import datetime, timezone

from sqlalchemy import text

from app.backup.schema import APP_ID, FORMAT_VERSION, schema_fingerprint_sql


def _tables(conn):
    return [r[0] for r in conn.execute(text("select table_name from pfs_registry order by 1"))] + ["audit_log"]


def collect_media(assets, fetcher):
    """Download media files and record successful and failed downloads."""
    files, entries = {}, []
    seen_refs = set()

    for asset in assets:
        ref = asset.get("file_ref")

        if not isinstance(ref, str) or not ref:
            entries.append({
                "file_ref": ref,
                "error": "invalid or missing file reference",
            })
            continue

        # Reject absolute paths, Windows paths and directory traversal.
        if (
            ref.startswith("/")
            or "\\" in ref
            or any(part in ("", ".", "..") for part in ref.split("/"))
        ):
            entries.append({
                "file_ref": ref,
                "error": "unsafe file name",
            })
            continue

        if ref in seen_refs:
            entries.append({
                "file_ref": ref,
                "error": "duplicate file reference",
            })
            continue

        seen_refs.add(ref)

        try:
            blob = fetcher(ref)

            if not isinstance(blob, bytes):
                raise TypeError("media fetcher did not return bytes")

        except Exception as exc:
            entries.append({
                "file_ref": ref,
                "error": str(exc)[:200],
            })
            continue

        files["media/" + ref] = blob

        entries.append({
            "file_ref": ref,
            "sha256": hashlib.sha256(blob).hexdigest(),
            "size": len(blob),
        })

    return files, entries


def build_backup(engine, *, include_media=False, media_fetcher=None) -> bytes:
    with engine.connect().execution_options(isolation_level="REPEATABLE READ") as conn:
        conn.execute(text("set local time zone 'UTC'"))
        tables = _tables(conn)
        fps = {r["table_name"]: r for r in conn.execute(text("select table_name, row_count, fingerprint, max_rev from pfs_table_fingerprints()")).mappings()}
        schema_fp = conn.execute(text(schema_fingerprint_sql(tables))).scalar()
        data = {t: conn.execute(text(f"""select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb)::text from "{t}" x""")).scalar() for t in tables}
    raw = json.dumps({"tables": data}, separators=(",", ":")).encode()
    assets = [
        a for a in json.loads(data["media_assets"])
        if not a.get("deleted_at")
    ]

    files = {}
    media = [
        {
            "file_ref": a["file_ref"],
            "content_hash": a.get("content_hash"),
        }
        for a in assets
    ]

    if not include_media:
        media_status = "not_requested"

    elif not media_fetcher:
        media_status = "unavailable"

    else:
        files, media = collect_media(assets, media_fetcher)

        successful = sum(1 for item in media if "error" not in item)
        failed = sum(1 for item in media if "error" in item)

        if failed == 0:
            media_status = "included"
        elif successful > 0:
            media_status = "partial"
        else:
            media_status = "failed"
    manifest = {"app": APP_ID, "format_version": FORMAT_VERSION, "exported_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "schema_fingerprint": schema_fp, "data_sha256": hashlib.sha256(raw).hexdigest(),
                "tables": {t: {"rows": len(json.loads(data[t])), "fingerprint": fps[t]["fingerprint"], "max_rev": fps[t]["max_rev"]} for t in tables},
                "media_included": media_status == "included",
                "media_status": media_status,
                "media": media,
                "restore": "Use backend/scripts/restore_backup.py on a clean, freshly migrated database."}
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("manifest.json", json.dumps(manifest, indent=2))
        z.writestr("data.json", raw)
        for path, blob in files.items():
            z.writestr(path, blob)
    return buf.getvalue()


def build_csv_export(engine) -> bytes:
    """One CSV file per table, for spreadsheets and other tools. It cannot be restored: use the full backup for that."""
    with engine.connect().execution_options(isolation_level="REPEATABLE READ") as conn:
        conn.execute(text("set local time zone 'UTC'"))
        tables = _tables(conn)
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
            counts = {}
            for t in tables:
                cols = [r[0] for r in conn.execute(text("select column_name from information_schema.columns where table_schema = 'public' and table_name = :t order by ordinal_position"), {"t": t})]
                out = io.StringIO()
                w = csv.writer(out)
                w.writerow(cols)
                n = 0
                for r in conn.execute(text(f'select to_jsonb(x) from "{t}" x order by x.id')):
                    row = r[0]
                    w.writerow(["" if row.get(c) is None else json.dumps(row[c]) if isinstance(row[c], (dict, list)) else row[c] for c in cols])
                    n += 1
                z.writestr(f"{t}.csv", out.getvalue())
                counts[t] = n
            z.writestr("README.txt", "One CSV file per table. Dates and times are ISO text; lists and objects are JSON text.\n"
                       "This export is for reading in a spreadsheet. To restore your data, use the full backup (JSON) instead.\n")
            z.writestr("manifest.json", json.dumps({"app": APP_ID, "format_version": FORMAT_VERSION, "kind": "csv_export", "rows": counts,
                                                    "exported_at": datetime.now(timezone.utc).isoformat(timespec="seconds")}, indent=2))
    return buf.getvalue()
