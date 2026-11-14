"""Shared by backup export and restore. Pure: no settings, no database driver."""
import re

FORMAT_VERSION = 1
APP_ID = "personal-fitness-system"


def schema_fingerprint_sql(tables):
    """SQL giving one hash of the column layout of the given tables. A backup only restores into a database with the same layout."""
    for t in tables:
        if not re.fullmatch(r"[a-z0-9_]+", t):
            raise ValueError(f"unsafe table name: {t}")
    names = ", ".join(f"'{t}'" for t in sorted(tables))
    return ("select md5(coalesce(string_agg(c.table_name || '.' || c.column_name || ':' || c.data_type, ',' order by c.table_name, c.ordinal_position), '')) "
            f"from information_schema.columns c where c.table_schema = 'public' and c.table_name in ({names})")
