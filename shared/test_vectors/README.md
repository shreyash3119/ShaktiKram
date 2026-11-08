# Test vectors

Shared test cases for the calculation rules in `../calculation_specs/`. The server (SQL `calc_*` functions) and later the phone (Dart) must both pass them.

Each file: `{ "function": "<name>", "cases": [ { "name": "...", "input": { ... }, "expect": { ... } } ] }`.
A case passes when every key in `expect` equals the result (extra keys in the result are allowed). Numbers match within 0.005.

Run on the server: `python3 backend/tests/run_vectors.py <database>` (also part of `backend/tests/run.sh`).
Add a case whenever a rule changes or a bug is found, then change the rule.
