#!/usr/bin/env python3
"""Runs every shared/test_vectors/*.json case against the SQL rule functions. Usage: run_vectors.py <db>
A case passes when every key in 'expect' matches the result (extra keys in the result are allowed)."""
import json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
db = sys.argv[1]
failures, total = [], 0

def call(fn, payload):
    arg = json.dumps(payload).replace("'", "''")
    out = subprocess.run(["psql", "-d", db, "-Atc", f"select {fn}('{arg}'::jsonb)"], check=True, capture_output=True, text=True).stdout.strip()
    return json.loads(out)

def same(exp, act):
    if isinstance(exp, dict):
        return isinstance(act, dict) and all(k in act and same(v, act[k]) for k, v in exp.items())
    if isinstance(exp, list):
        return isinstance(act, list) and len(exp) == len(act) and all(same(a, b) for a, b in zip(exp, act))
    if isinstance(exp, (int, float)) and not isinstance(exp, bool):
        return isinstance(act, (int, float)) and not isinstance(act, bool) and abs(exp - act) < 0.005
    return exp == act

for f in sorted((ROOT / "shared" / "test_vectors").glob("*.json")):
    spec = json.load(open(f, encoding="utf-8"))
    for case in spec["cases"]:
        total += 1
        got = call(spec["function"], case["input"])
        if not same(case["expect"], got):
            failures.append(f"{f.name}: {case['name']}\n   expected {case['expect']}\n   got      {got}")
if failures:
    print("TEST VECTORS FAILED"); [print(" -", x) for x in failures]; sys.exit(1)
print(f"test vectors passed: {total} cases")
