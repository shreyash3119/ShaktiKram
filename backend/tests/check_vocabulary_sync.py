#!/usr/bin/env python3
"""Fails if the database and shared/vocabulary/*.json disagree. Usage: check_vocabulary_sync.py <db>"""
import json, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VOC = ROOT / "shared" / "vocabulary"
sys.path.insert(0, str(VOC))
from generate_sql import CHECKS as CHECKS_1, CHECKS_2, CHECKS_3  # noqa: E402
CHECKS = CHECKS_1 + CHECKS_2 + CHECKS_3

db = sys.argv[1]
load = lambda n: json.load(open(VOC / n, encoding="utf-8"))
def q(sql):
    return subprocess.run(["psql", "-d", db, "-Atc", sql], check=True, capture_output=True, text=True).stdout.strip().splitlines()

errors = []
def same(name, expected, actual):
    if sorted(expected) != sorted(actual):
        errors.append(f"{name}: json {sorted(set(expected) ^ set(actual))} differ from database")

m = load("muscles.json")["muscles"]
same("muscles", [f'{x["key"]}|{x["group"]}|{x["label"]}' for x in m], q("select key||'|'||group_key||'|'||label from muscles where not is_custom"))
same("body_regions", [f'{x["key"]}|{x["label"]}' for x in load("body_regions.json")["body_regions"]], q("select key||'|'||label from body_regions where not is_custom"))
same("equipment", [f'{x["key"]}|{x["label"]}' for x in load("equipment.json")["equipment"]], q("select key||'|'||label from equipment where not is_custom"))
st = load("statuses.json")
for t, c, l in CHECKS:
    d = " ".join(q(f"select pg_get_constraintdef(oid) from pg_constraint where conname = 'ck_{t}_{c}_values'"))
    if not d:
        errors.append(f"missing constraint ck_{t}_{c}_values"); continue
    same(f"{t}.{c}", st[l], re.findall(r"'([^']+)'::text", d))
# numeric scales: the CHECK bounds must match shared/vocabulary/scales.json
sc = load("scales.json")
dev, pri, pain, ci = sc["muscle_development_level"], sc["muscle_priority"], sc["pain_level"], sc["checkin_scale"]
bounds = [("ck_muscle_assessment_items_level", dev["min"], dev["max"]), ("ck_muscle_priorities_priority", pri["min"], pri["max"]),
          ("ck_pain_entries_level", pain["min"], pain["max"])] + [(f"ck_daily_checkins_{f}", ci["min"], ci["max"]) for f in ci["fields"]]
for name, lo, hi in bounds:
    d = " ".join(q(f"select pg_get_constraintdef(oid) from pg_constraint where conname = '{name}'"))
    if f">= {lo}" not in d or f"<= {hi}" not in d:
        errors.append(f"{name}: expected bounds {lo}..{hi}, database has: {d or 'missing'}")
cats = dict(zip(*[iter(sum(([k, v] for k, v in dev["categories_from_latest_level"].items()), []))] * 2))
for k, v in cats.items():
    got = " ".join(q(f"select pfs_muscle_category({k})"))
    if got != v:
        errors.append(f"pfs_muscle_category({k}) is {got}, json says {v}")
if errors:
    print("VOCABULARY OUT OF SYNC"); [print(" -", e) for e in errors]; sys.exit(1)
print(f"vocabulary in sync: {len(m)} muscles, body regions, equipment, {len(CHECKS)} check constraints")
