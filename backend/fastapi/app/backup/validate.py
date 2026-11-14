"""Checks a backup file without touching any database: format, file hash, row counts and media hashes.
Each entry of `data` is the JSON text of one table, exactly as PostgreSQL wrote it."""
import hashlib
import io
import json
import zipfile

from app.backup.schema import APP_ID, FORMAT_VERSION


def validate_backup(blob: bytes) -> dict:
    errors, warnings = [], []
    manifest, data = None, None

    def result():
        tables = (manifest or {}).get("tables", {})

        if not isinstance(tables, dict):
            tables = {}

        counts = {
            table: info["rows"]
            for table, info in tables.items()
            if isinstance(info, dict)
            and isinstance(info.get("rows"), int)
            and not isinstance(info.get("rows"), bool)
            and info["rows"] >= 0
        }
        return {
            "ok": not errors,
            "errors": errors,
            "warnings": warnings,
            "manifest": manifest,
            "data": data if not errors else None,
            "counts": counts,
        }

    if not isinstance(blob, bytes) or not blob:
        errors.append("backup file is empty or invalid")
        return result()

    try:
        with zipfile.ZipFile(io.BytesIO(blob), "r") as z:
            entries = z.infolist()
            names = [entry.filename for entry in entries]

            # Reject duplicate archive entries.
            if len(names) != len(set(names)):
                errors.append("backup contains duplicate ZIP entries")
                return result()

            name_set = set(names)

            for required in ("manifest.json", "data.json"):
                if required not in name_set:
                    errors.append(f"{required} is missing")

            if errors:
                return result()

            # Read and parse manifest.
            try:
                manifest_raw = z.read("manifest.json")
                manifest = json.loads(manifest_raw.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError, KeyError, RuntimeError):
                errors.append("manifest.json is invalid or damaged")
                return result()

            if not isinstance(manifest, dict):
                errors.append("manifest must contain a JSON object")
                return result()

            required_fields = {
    "app",
    "format_version",
    "exported_at",
    "schema_fingerprint",
    "data_sha256",
    "tables",
}

            missing = required_fields - manifest.keys()
            if missing:
                errors.append(
                    "manifest is missing required fields: "
                    + ", ".join(sorted(missing))
                )
                return result()
            if (
                not isinstance(manifest.get("exported_at"), str)
                or not manifest["exported_at"].strip()
            ):
                errors.append("Invalid or missing exported_at")

            if (
                not isinstance(manifest.get("schema_fingerprint"), str)
                or not manifest["schema_fingerprint"].strip()
            ):
                errors.append("Invalid or missing schema_fingerprint")

            if manifest["app"] != APP_ID:
                errors.append("this backup was not made by this app")

            if manifest["format_version"] != FORMAT_VERSION:
                errors.append(
                    f"unsupported backup format version: "
                    f"{manifest['format_version']}"
                )

            if not isinstance(manifest["data_sha256"], str):
                errors.append("manifest data_sha256 must be a string")

            tables_info = manifest["tables"]

            if not isinstance(tables_info, dict):
                errors.append("manifest tables must be a JSON object")
                return result()

            for table, info in tables_info.items():
                if not isinstance(table, str) or not table:
                    errors.append("manifest contains an invalid table name")
                    continue

                if not isinstance(info, dict):
                    errors.append(f"table {table}: invalid manifest entry")
                    continue

                required_table_fields = {"rows", "fingerprint", "max_rev"}
                missing_table_fields = required_table_fields - set(info)

                if missing_table_fields:
                    errors.append(
                        f"table {table}: missing metadata: "
                        + ", ".join(sorted(missing_table_fields))
                    )
                    continue

                if (
                    not isinstance(info["rows"], int)
                    or isinstance(info["rows"], bool)
                    or info["rows"] < 0
                ):
                    errors.append(f"table {table}: invalid expected row count")

                if (
                    not isinstance(info["fingerprint"], str)
                    or not info["fingerprint"].strip()
                ):
                    errors.append(f"table {table}: invalid fingerprint")

                

            # Read and verify data.json.
            try:
                raw = z.read("data.json")

                if hashlib.sha256(raw).hexdigest() != manifest["data_sha256"]:
                    errors.append(
                        "data.json does not match its recorded hash "
                        "(the file was changed or damaged)"
                    )
                else:
                    parsed = json.loads(raw.decode("utf-8"))

                    if not isinstance(parsed, dict):
                        errors.append("data.json must contain a JSON object")
                    elif not isinstance(parsed.get("tables"), dict):
                        errors.append(
                            "data.json must contain a tables JSON object"
                        )
                    else:
                        data = parsed["tables"]

            except (UnicodeDecodeError, json.JSONDecodeError, KeyError, RuntimeError):
                errors.append("data.json is invalid or damaged")

            if data is not None:
                # Check table presence and row counts.
                for table, info in tables_info.items():
                    if table not in data:
                        errors.append(
                            f"table {table} is missing from data.json"
                        )
                        continue

                    if not isinstance(info, dict):
                        continue

                    try:
                        table_rows = json.loads(data[table])

                        if not isinstance(table_rows, list):
                            errors.append(
                                f"table {table}: data must be a JSON array"
                            )
                            continue

                        expected = info.get("rows")

                        if (
                            isinstance(expected, int)
                            and not isinstance(expected, bool)
                            and len(table_rows) != expected
                        ):
                            errors.append(
                                f"table {table}: {len(table_rows)} rows, "
                                f"expected {expected}"
                            )

                    except (
                        TypeError,
                        UnicodeDecodeError,
                        json.JSONDecodeError,
                    ):
                        errors.append(
                            f"table {table}: invalid JSON table data"
                        )

                # Detect unexpected tables in data.json.
                extra_tables = set(data) - set(tables_info)
                for table in sorted(extra_tables):
                    errors.append(
                        f"table {table} exists in data.json "
                        "but is missing from the manifest"
                    )

            # Validate media metadata.
            media = manifest.get("media", [])
            media_included = manifest.get("media_included", False)
            media_status = manifest.get(
                "media_status",
                "included" if media_included else "not_requested",
            )

            valid_media_statuses = {
                "not_requested",
                "unavailable",
                "included",
                "partial",
                "failed",
            }

            if (
                not isinstance(media_status, str)
                or media_status not in valid_media_statuses
            ):
                errors.append(f"invalid media_status: {media_status}")
                media_status = "not_requested"

            if media_included != (media_status == "included"):
                errors.append("media_included does not match media_status")

            if not isinstance(media, list):
                errors.append("manifest media must be a JSON array")
                media = []

            if not isinstance(media_included, bool):
                errors.append("manifest media_included must be a boolean")
                media_included = False

            seen_media = set()

            for item in media:
                if not isinstance(item, dict):
                    errors.append("manifest contains an invalid media entry")
                    continue

                ref = item.get("file_ref")

                if not isinstance(ref, str) or not ref:
                    errors.append("media entry has an invalid file_ref")
                    continue

                # Prevent absolute paths and directory traversal.
                if (
                    ref.startswith("/")
                    or "\\" in ref
                    or any(part in ("", ".", "..") for part in ref.split("/"))
                ):
                    errors.append(f"unsafe media file reference: {ref}")
                    continue

                if ref in seen_media:
                    errors.append(f"duplicate media reference: {ref}")
                    continue

                seen_media.add(ref)

                # A failed download is a warning, not a missing-file error.
                if "error" in item:
                    warnings.append(
                        f"media file {ref} was not included: {item['error']}"
                    )
                    continue

                # When media is excluded, the manifest can list references
                # without embedding their files in the archive.
                if media_status not in ("included", "partial"):
                    continue

                path = "media/" + ref

                if path not in name_set:
                    errors.append(f"media file {ref} is missing")
                    continue

                expected_hash = item.get("sha256")

                if not isinstance(expected_hash, str):
                    errors.append(
                        f"media file {ref} has no valid recorded SHA-256 hash"
                    )
                    continue

                try:
                    media_blob = z.read(path)
                    actual_hash = hashlib.sha256(media_blob).hexdigest()

                    if actual_hash != expected_hash:
                        errors.append(
                            f"media file {ref} does not match its recorded hash"
                        )

                except (KeyError, RuntimeError, zipfile.BadZipFile):
                    errors.append(f"media file {ref} is damaged")

            if media_status == "partial":
                warnings.append(
            "some media files were not included; "
            "check the media entries for download errors"
            )

            elif media_status == "unavailable":
                warnings.append(
                    "media was requested but no media fetcher was available"
                )

            elif media_status == "failed":
                warnings.append(
                    "no media files could be downloaded"
                )

            elif media_status == "not_requested" and media:
                warnings.append(
                    "media files are not part of this backup; "
                    "copy the media bucket separately"
                )

    except zipfile.BadZipFile:
        errors.append("not a backup file (not a valid ZIP archive)")

    except (OSError, EOFError, RuntimeError):
        errors.append("backup archive is damaged or cannot be read")

    return result()