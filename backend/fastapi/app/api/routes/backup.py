from datetime import datetime, timezone

import httpx
from fastapi import APIRouter, Depends, File, HTTPException, Query, Response, UploadFile

from app.backup.export import build_backup, build_csv_export
from app.backup.validate import validate_backup
from app.core.auth import Owner, require_owner
from app.core.config import settings
from app.database.connection import engine

router = APIRouter(prefix="/backup", tags=["Backup"], dependencies=[Depends(require_owner)])
MAX_UPLOAD = 200 * 1024 * 1024


def _media_fetcher(token: str):
    """Downloads a media file from private storage with the owner's own session (never a service key)."""
    def fetch(ref: str) -> bytes:
        r = httpx.get(f"{settings.SUPABASE_URL}/storage/v1/object/authenticated/media/{ref}", timeout=60,
                      headers={"Authorization": f"Bearer {token}", "apikey": settings.SUPABASE_ANON_KEY})
        r.raise_for_status()
        return r.content
    return fetch


@router.get("/export")
def export(owner: Owner = Depends(require_owner), format: str = Query("zip", pattern="^(zip|csv)$"), include_media: bool = False):
    if include_media and not settings.SUPABASE_URL:
        raise HTTPException(status_code=503, detail="Media download needs SUPABASE_URL to be configured")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    if format == "csv":
        return Response(build_csv_export(engine), media_type="application/zip", headers={"Content-Disposition": f'attachment; filename="fitness-export-{stamp}.zip"'})
    blob = build_backup(engine, include_media=include_media, media_fetcher=_media_fetcher(owner.token) if include_media else None)
    return Response(blob, media_type="application/zip", headers={"Content-Disposition": f'attachment; filename="fitness-backup-{stamp}.zip"'})


@router.post("/validate")
async def validate(file: UploadFile = File(...)):
    blob = await file.read(MAX_UPLOAD + 1)
    if len(blob) > MAX_UPLOAD:
        raise HTTPException(status_code=413, detail="Backup file is too large")
    r = validate_backup(blob)
    m = r["manifest"] or {}
    return {"ok": r["ok"], "errors": r["errors"], "warnings": r["warnings"], "counts": r["counts"], "exported_at": m.get("exported_at"),
            "format_version": m.get("format_version"), "media_included": m.get("media_included")}
