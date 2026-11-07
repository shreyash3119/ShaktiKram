# Backend Stages

The backend is completed as one major phase before full frontend work begins.
Modules inside a stage can be built in parallel by the three contributors.

| Stage | Name | Main deliverable |
| --- | --- | --- |
| 0 | Preparation and technical contracts | Approved conventions, shared vocabulary, repo structure |
| 1 | Infrastructure and database foundation | Supabase project, migrations, reference/profile/settings tables, audit log, private storage, backups, seed data, owner and device access, the single write function, pull by revision |
| 2 | Core training backend | Exercises, splits, templates, sessions, sets, schedule, attendance, planned breaks, history comparison |
| 3 | Body and lifestyle backend | Measurements, assessments, injuries, recovery, sleep, supplements, meals, hydration, cardio, steps |
| 4 | Intelligence and progression | Progression, est. 1RM, PRs, volume, exposure, readiness, deload, goals, plateaus, daily briefing |
| 5 | Reports, exports and backup | Monthly/quarterly/half-yearly/yearly/custom/complete reports, Excel, PDF, full backup and restore |
| 6 | Offline synchronization | Client outbox and offline behaviour, retries, two-device and interrupted-sync tests, media upload recovery (the server write and pull functions are built in Stage 1) |
| 7 | Integration, security and release readiness | Full tests, security verification, API docs, sample data, sign-off |

## Where each of the 26 modules lands

| Stage | Modules (feature numbers) |
| --- | --- |
| 1 | 1 Profile and goals (tables), 16 Data management and settings (settings, audit), reminder rules (table), equipment (reference), access control and sync core |
| 2 | 2 Splits, 3 Exercises, 4 Workout recording, 5 Schedule and attendance, 19 Planned breaks, 23 Exercise library, 24 Equipment and alternatives (data), 26 Templates |
| 3 | 7 Body measurements, 8 Supplements, 9 Cardio and activity, 10 Recovery and sleep, 11 Meals, 12 Nutrition and hydration, 17 Muscle assessment (ratings), 18 Injury and pain, 20 Daily check-in (records) |
| 4 | 6 Progression, 14 Intelligence, 15 Dashboard data, 17 Muscle exposure, 20 Readiness summary, 21 Deload, 22 Goal progress and milestones, 24 Alternative ranking, 25 PRs and achievements |
| 5 | 13 Reports, 16 Export, backup and restore |
| 6 | Offline sync across all modules |
| 7 | Integration, security, release readiness |

## Stage 0 exit criteria

- [ ] TECHNICAL_CONTRACT.md reviewed and approved
- [ ] DECISIONS.md conflicts resolved and confirmed
- [ ] Shared vocabulary files approved
- [ ] Module ownership agreed (Person A / B / C)
- [ ] Repository created with branch strategy (main, develop, feature/*)

### Stage 0 work status

Drafted and ready for review:

- [x] `docs/TECHNICAL_CONTRACT.md` (naming, columns, units, dates, versioning, audit, security, API envelope, sync, calculations, wording, definition of done)
- [x] `docs/DECISIONS.md` (D1 to D12)
- [x] `docs/TEAM_RESPONSIBILITIES.md` (ownership, branches, review rules)
- [x] `shared/vocabulary/` (muscles, body regions, statuses, scales, units) with `validate.py`, which passes
- [x] `shared/api_contracts/error_codes.json`
- [x] Folder structure for backend, shared and docs
- [ ] Review and approval by all three contributors (decisions D2, D3 and D12 were settled by the project owner on 5 Nov 2026; contributor sign-off is still open)
- [ ] Git repository initialised and `develop` branch created (do this on your machine or GitHub)

## Stage 1: done (5 Nov 2026)

All of Stage 1 is built and tested on PostgreSQL 16 (`backend/tests/run.sh`):

- [x] Migrations `20261106000100` to `20261106000800`: common-column triggers, uuid_v7, audit log, versioning guard, restore mode
- [x] Reference tables: `muscles`, `body_regions`, `equipment`, with seeded rows protected; `exercises` stub for foreign keys
- [x] `profile_versions` (versioned), `settings` (one row), `goals` with automatic status history, `reminder_rules`
- [x] Owner and device access: `app_owner`, `devices`, `api_claim_owner`, `api_register_device`, `api_list_devices`, `api_revoke_device`
- [x] Sync core: `sync_operations`, `api_apply_operations` (idempotent, ordered, per-operation isolation, write lock, conflict rules), `api_pull_changes`
- [x] RLS on every table (a test fails the build otherwise), no direct write grants, private storage buckets
- [x] Backups: `scripts/backup.sh`, `scripts/restore_verify.sh`, `BACKUPS.md`; logical restore mode
- [x] Vocabulary: DB-versus-JSON sync test; generated seed and CHECK migrations
- [x] Fictional development seed data (`seed.sql`)
- [x] Contract gaps from the Stage 0 review closed (D12 to D17)

Not verified in this environment: `config.toml` against the Supabase CLI, and a run on a real Supabase project (tests use plain PostgreSQL with stand-ins for `auth` and `storage`).

## Stage 2: done (7 Nov 2026)

All of Stage 2 is built and tested on PostgreSQL 16 (`backend/tests/run.sh`, 8 test files):

- [x] Exercises (extended), `exercise_muscles`, `exercise_alternatives`
- [x] Templates: `workout_templates`, `template_versions`, `template_exercises` (the prescription), sealed once used
- [x] Splits: `splits` (one active), `split_versions`, `split_days`, `split_day_muscles`, `split_status_events`
- [x] Schedule and breaks: `schedule_entries`, `gym_decisions`, `planned_breaks`, `break_events`
- [x] Sessions: `workout_sessions`, `session_exercises` (prescription snapshot kept automatically), `sets`
- [x] Views: session summary, exercise comparison with previous session, weekly volume, exercise usage, split periods, daily attendance, weekly consistency, current streak
- [x] `api_compare_template_versions`; every table is writable through `api_apply_operations`
- [x] Hardening: `btree_gist` moved out of `public`; global default of no execute on new functions (D23)
- [x] Stage 1 follow-ups: safer `run.sh`, FastAPI defaults, REST smoke test script

Not verified: the REST smoke test (`backend/scripts/smoke_rest.sh`) has only been syntax-checked. Run it against local Supabase.

Left for later stages: muscle exposure per week and progression (Stage 4), attendance reminders (Stage 3 reminder queries), reports (Stage 5).

## Backend completion criteria

All tables and relationships implemented; all 26 modules have working operations;
history preservation, versioning and audit tested; calculations covered by shared
test vectors; API contracts documented; offline sync tested; valid Excel/PDF
exports; backup and restore verified; private access verified; test data and API
docs available; all contributors reviewed integration.
