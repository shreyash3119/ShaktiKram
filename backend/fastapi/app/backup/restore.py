"""Restores a backup into a CLEAN, freshly migrated database. A server-side operation (not an API route): it needs a role that can write.
Everything happens in one transaction and is checked before it is kept: foreign keys, row counts and a content hash for every table.
Nothing is written if the backup file is damaged, the database layout differs, or the target is not clean."""
import json

import psycopg
from psycopg import sql

from app.backup.schema import schema_fingerprint_sql
from app.backup.validate import validate_backup

KEPT_TABLES = {"muscles", "body_regions", "equipment", "settings", "audit_log"}   # these hold rows even in a fresh database
SEEDED_REFERENCE = ("muscles", "body_regions", "equipment")


class RestoreError(Exception):
    pass


def _check_target(conn, tables, data, manifest, force_schema):
    if set(tables) != set(data):
        raise RestoreError(f"the database and the backup have different tables: {sorted(set(tables) ^ set(data))}")
    if conn.execute(schema_fingerprint_sql(tables)).fetchone()[0] != manifest["schema_fingerprint"] and not force_schema:
        raise RestoreError("the database layout differs from the backup. Apply the same migrations first (or use force_schema at your own risk).")
    for t in tables:
        if t not in KEPT_TABLES:
            n = conn.execute(f'select count(*) from "{t}"').fetchone()[0]
            if n:
                raise RestoreError(f"the target database is not clean: {t} already has {n} rows")
    if conn.execute("select count(*) from audit_log where table_name <> 'settings'").fetchone()[0]:
        raise RestoreError("the target database is not clean: the audit log already holds history")
    for t in SEEDED_REFERENCE:
        if conn.execute(f'select count(*) from "{t}" where is_custom').fetchone()[0]:
            raise RestoreError(f"the target database is not clean: {t} contains custom rows")


def restore(conninfo: str, blob: bytes, *, force_schema: bool = False, check_only: bool = False) -> dict:
    check = validate_backup(blob)
    if not check["ok"]:
        raise RestoreError("the backup file is not valid: " + "; ".join(check["errors"]))
    manifest, data = check["manifest"], check["data"]
    try:
        with psycopg.connect(conninfo) as conn:
            tables = [r[0] for r in conn.execute("select table_name from pfs_registry order by 1")] + ["audit_log"]
            _check_target(conn, tables, data, manifest, force_schema)
            conn.rollback()
            if check_only:
                return {"checked": True, "tables": len(tables), "exported_at": manifest["exported_at"], "media_included": manifest["media_included"]}
            fks = conn.execute("""
                SELECT
                    n.nspname,
                    r.relname,
                    c.conname,
                    c.condeferrable,
                    c.condeferred
                FROM pg_constraint c
                JOIN pg_class r ON r.oid = c.conrelid
                JOIN pg_namespace n ON n.oid = r.relnamespace
                WHERE c.contype = 'f'
                AND n.nspname = 'public'
            """).fetchall()

            try:
                # Temporarily defer all foreign keys during restoration.
                for schema, table, name, was_deferrable, was_deferred in fks:
                    conn.execute(
                        sql.SQL(
                            "ALTER TABLE {}.{} ALTER CONSTRAINT {} "
                            "DEFERRABLE INITIALLY DEFERRED"
                        ).format(
                            sql.Identifier(schema),
                            sql.Identifier(table),
                            sql.Identifier(name),
                        )
                    )

                conn.execute("set local pfs.restore_mode = 'on'")
                conn.execute("set local pfs.allow_purge = 'on'")
                conn.execute("set local time zone 'UTC'")

                conn.execute(
                    "alter table audit_log disable trigger a_audit_log_no_change"
                )

                for t in tables:
                    conn.execute(f'delete from "{t}"')

                conn.execute(
                    "alter table audit_log enable trigger a_audit_log_no_change"
                )

                for t in tables:
                    if data[t] != "[]":
                        conn.execute(
                            f'insert into "{t}" '
                            f'select * from jsonb_populate_recordset(null::"{t}", %s::jsonb)',
                            (data[t],),
                        )

                # Validate all foreign keys before accepting restored data.
                conn.execute("set constraints all immediate")

                got = {
                    r[0]: (r[1], r[2])
                    for r in conn.execute(
                        "select table_name, row_count, fingerprint "
                        "from pfs_table_fingerprints()"
                    )
                }

                bad = [
                    t for t in tables
                    if got.get(t) != (
                        manifest["tables"][t]["rows"],
                        manifest["tables"][t]["fingerprint"],
                    )
                ]

                if bad:
                    raise RestoreError(
                        f"the restored data does not match the backup for: "
                        f"{bad}. Nothing was changed."
                    )

                conn.execute("select pfs_restore_finish()")

                # Restore the original foreign-key settings.
                for schema, table, name, was_deferrable, was_deferred in fks:
                    if was_deferrable:
                        setting = (
                            "DEFERRABLE INITIALLY DEFERRED"
                            if was_deferred
                            else "DEFERRABLE INITIALLY IMMEDIATE"
                        )
                    else:
                        setting = "NOT DEFERRABLE"

                    conn.execute(
                        sql.SQL(
                            "ALTER TABLE {}.{} ALTER CONSTRAINT {} "
                            + setting
                        ).format(
                            sql.Identifier(schema),
                            sql.Identifier(table),
                            sql.Identifier(name),
                        )
                    )

                conn.commit()

            except Exception:
                conn.rollback()
                raise
    except psycopg.Error as e:
        raise RestoreError(f"database error, nothing was kept: {e}") from e
    return {"checked": False, "tables": len(tables), "rows": {t: len(json.loads(data[t])) for t in tables if data[t] != "[]"},
            "exported_at": manifest["exported_at"], "media_included": manifest["media_included"]}
