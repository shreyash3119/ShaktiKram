"""Reads the shared vocabulary (single source: shared/vocabulary). No private copies of value lists."""
import json
from functools import lru_cache
from pathlib import Path

from app.core.config import settings


def shared_dir() -> Path:
    if settings.SHARED_DIR:
        return Path(settings.SHARED_DIR)
    return Path(__file__).resolve().parents[4] / "shared"


@lru_cache
def statuses() -> dict:
    with open(shared_dir() / "vocabulary" / "statuses.json", encoding="utf-8") as f:
        return json.load(f)


def report_periods() -> list:
    return statuses()["report_period"]
