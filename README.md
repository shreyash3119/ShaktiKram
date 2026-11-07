# Personal Fitness Management System

A personal fitness management system for one user. One backend and a Flutter mobile app with offline support.
The web client is on hold until the mobile app exists (decision D2).

**Development order:** backend completion -> Flutter foundation -> mobile -> web -> release.

## Repository layout

```
Personal-Fitness-System/
├── backend/
│   ├── supabase/        migrations, seed.sql, functions, config.toml
│   ├── fastapi/         optional; reports, exports, heavy calculations
│   ├── tests/
│   └── README.md
├── mobile_web/          Flutter app (added after backend sign-off)
├── shared/
│   ├── vocabulary/      muscles, scales, statuses, units (single source)
│   ├── api_contracts/   request/response definitions
│   ├── calculation_specs/  plain-language rules with examples
│   └── test_vectors/    shared inputs/expected outputs
└── docs/
    ├── DECISIONS.md
    ├── BACKEND_STAGES.md
    ├── TECHNICAL_CONTRACT.md
    └── (further documents added per stage)
```

## Current status

- Stage 0 (preparation and technical contracts): done, contributor sign-off pending
- Stage 1 (infrastructure and database foundation): done and tested (`backend/tests/run.sh`)
- Stage 2 (core training backend): done and tested
- Stage 3 (body and lifestyle backend): done and tested
- Stages 4-7: not started

## Ground rules

1. Do not start a stage's code before its contract is reviewed.
2. Shared vocabulary lives only in `shared/vocabulary/`. No private copies.
3. History is never overwritten: plans are versioned, facts are append-only, insights are rebuildable.
4. Manual muscle-development ratings are user-entered and never calculated.
5. The app gives observations and suggestions, never diagnoses or medical advice.
