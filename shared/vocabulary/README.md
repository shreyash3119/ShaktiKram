# Shared vocabulary

Single source for every list of named values. No other layer keeps its own copy.

| File | Contents | Becomes in the database |
| --- | --- | --- |
| `muscles.json` | Muscle regions and groups | `muscles` reference table |
| `body_regions.json` | Body regions and sides for injuries and pain | `body_regions` reference table |
| `statuses.json` | Closed value lists | `CHECK` constraints |
| `scales.json` | Numeric scales with labels | `CHECK` range constraints |
| `equipment.json` | Gym equipment list | `equipment` reference table |
| `units.json` | Canonical units and column suffixes | Column types and names |

Items marked `proposed` go beyond the written specification. Confirm them at Stage 0 review.

Check the files with:

```
python3 -I shared/vocabulary/validate.py
```

Changing a value: edit the JSON, add a migration, update tests, and get review from all three contributors.
