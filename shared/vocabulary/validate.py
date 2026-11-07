#!/usr/bin/env python3
"""Validate the shared vocabulary files. Exit code 1 on any problem."""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SNAKE = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$")
errors = []


def load(name):
    with open(HERE / name, encoding="utf-8") as f:
        return json.load(f)


def check(cond, msg):
    if not cond:
        errors.append(msg)


# muscles
m = load("muscles.json")
groups = set(m["groups"])
keys = [x["key"] for x in m["muscles"]]
check(len(keys) == len(set(keys)), "muscles: duplicate keys")
for x in m["muscles"]:
    check(bool(SNAKE.match(x["key"])), f"muscles: bad key {x['key']}")
    check(x["group"] in groups, f"muscles: unknown group for {x['key']}")
for g in groups:
    check(any(x["group"] == g for x in m["muscles"]), f"muscles: group {g} has no muscles")

# body regions
b = load("body_regions.json")
bk = [x["key"] for x in b["body_regions"]]
check(b["sides"] == load("statuses.json")["body_side"], "body_regions sides must equal statuses body_side")
check(len(bk) == len(set(bk)), "body_regions: duplicate keys")
for k in bk:
    check(bool(SNAKE.match(k)), f"body_regions: bad key {k}")

# statuses
s = load("statuses.json")
for name, values in s.items():
    if name.startswith("_") or name == "version":
        continue
    check(bool(SNAKE.match(name)), f"statuses: bad list name {name}")
    check(isinstance(values, list) and len(values) >= 2, f"statuses: {name} needs 2+ values")
    check(len(values) == len(set(values)), f"statuses: duplicates in {name}")
    for v in values:
        check(bool(SNAKE.match(v)), f"statuses: bad value {v} in {name}")

# scales
sc = load("scales.json")
dev = sc["muscle_development_level"]
check(dev["min"] == 1 and dev["max"] == 5, "scales: muscle development must be 1..5")
check(set(dev["labels"]) == {"1", "2", "3", "4", "5"}, "scales: development labels must cover 1..5")
check(set(dev["categories_from_latest_level"]) == set(dev["labels"]), "scales: categories must cover every level")
pri = sc["muscle_priority"]
check(pri["min"] == 1 and pri["max"] == 3, "scales: priority must be 1..3")
check(sc["pain_level"]["min"] == 0 and sc["pain_level"]["max"] == 10, "scales: pain must be 0..10")
for name, v in sc.items():
    if isinstance(v, dict) and "min" in v:
        check(v["min"] < v["max"], f"scales: {name} min must be below max")

# equipment
q = load("equipment.json")
qk = [x["key"] for x in q["equipment"]]
check(len(qk) == len(set(qk)), "equipment: duplicate keys")
for k in qk:
    check(bool(SNAKE.match(k)), f"equipment: bad key {k}")
check(len(set(dev["categories_from_latest_level"].values())) == 5, "scales: need one category per level")
ci = sc["checkin_scale"]
check(set(ci["directions"]) == set(ci["fields"]), "scales: every check-in field needs a direction")
check(set(ci["directions"].values()) <= {"higher_is_better", "higher_is_worse"}, "scales: bad check-in direction")

# units
u = load("units.json")
suffixes = [v["suffix"] for v in u["canonical"].values()]
check(len(suffixes) == len(set(suffixes)), "units: duplicate suffixes")
for k, v in u["canonical"].items():
    check(v["suffix"].startswith("_"), f"units: suffix of {k} must start with underscore")

# error codes
e = load("../api_contracts/error_codes.json")
codes = [x["code"] for x in e["errors"]]
check(len(codes) == len(set(codes)), "error_codes: duplicate codes")
for x in e["errors"]:
    check(bool(SNAKE.match(x["code"])), f"error_codes: bad code {x['code']}")
    check(400 <= x["http"] < 600, f"error_codes: bad http status for {x['code']}")

if errors:
    print("FAILED")
    for x in errors:
        print(" -", x)
    sys.exit(1)

print(
    f"OK: {len(keys)} muscles in {len(groups)} groups, {len(bk)} body regions, "
    f"{sum(1 for k in s if not k.startswith('_') and k != 'version')} status lists, "
    f"{len(qk)} equipment items, {len(codes)} error codes"
)
