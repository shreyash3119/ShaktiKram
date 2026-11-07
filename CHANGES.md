# Stage 3 changes: how to apply

Unzip over your repository root (it only contains new and changed files), then:

1. `git status` should show the files listed below. Run `bash backend/tests/run.sh`.
2. Local Supabase: `cd backend && supabase db reset` applies the 8 new migrations.
3. Hosted project: take a backup (`backend/scripts/backup.sh`), then `supabase db push`.
4. Optional: run `backend/scripts/smoke_rest.sh` again.

## What is new
- Migrations `20261108000100` to `20261108000700` (check-in, sleep, steps, cardio; body and injuries; muscle assessment; supplements; meals and targets; vocabulary checks; reminder validation; views and functions)
- Tests `90` to `93`; `shared/api_contracts/stage3_entities.md`
- Decisions D24 to D30, contract section 16, Stage 3 status
- `statuses.json` gains `body_side`; the vocabulary check now also verifies numeric scale bounds and muscle categories against the database
