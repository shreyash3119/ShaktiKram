# Stage 4 changes: how to apply

Unzip over your repository root (it only contains new and changed files), then:

1. Delete the two empty placeholder files `shared/calculation_specs/.gitkeep` and `shared/test_vectors/.gitkeep` (the folders now have real files).
2. `git status` should show the files listed below. Run `bash backend/tests/run.sh` (it now also runs the shared test cases).
3. Local Supabase: `cd backend && supabase db reset` applies the 6 new migrations.
4. Hosted project: take a backup (`backend/scripts/backup.sh`), then `supabase db push`.

## What is new
- Migrations `20261109000100` to `20261109000600`: tables, vocabulary checks, calculation rules, record detection, views, suggestion and briefing functions
- `shared/calculation_specs/` (rules in plain language), `shared/test_vectors/` (50 shared cases), `backend/tests/run_vectors.py`
- Tests `94` to `96`; `shared/api_contracts/stage4_entities.md`
- Decisions D31 to D37, contract section 17, Stage 4 status
- `statuses.json` gains `workout_volume` (record kind), `achievement_kind` and `media_type`
