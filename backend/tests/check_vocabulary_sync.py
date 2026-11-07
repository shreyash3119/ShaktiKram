#!/usr/bin/env python3
"""Fails if the database and shared/vocabulary/*.json disagree. Usage: check_vocabulary_sync.py <db>"""
import json, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VOC = ROOT / "shared" / "vocabulary"
sys.path.insert(0, str(VOC))
from generate_sql import CHECKS as CHECKS_1, CHECKS_2  # noqa: E402
CHECKS = CHECKS_1 + CHECKS_2

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
if errors:
    print("VOCABULARY OUT OF SYNC"); [print(" -", e) for e in errors]; sys.exit(1)
print(f"vocabulary in sync: {len(m)} muscles, body regions, equipment, {len(CHECKS)} check constraints")
