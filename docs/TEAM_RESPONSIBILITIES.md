# Team Responsibilities and Git Workflow

Names for Person A, B and C are to be filled in at review.

## Ownership

| Area | Person | Backend scope |
| --- | --- | --- |
| Database foundation, migrations, common columns and triggers, audit, private access, backups, sync | A | Stages 1 and 6 |
| Core training: exercises, splits, templates, sessions, sets, schedule, attendance, breaks | A | Stage 2 |
| Body, injuries, pain, restrictions, check-ins, sleep, supplements, meals, hydration, cardio, steps | B | Stage 3 |
| Reminder rules and notification due-queries | B | Stage 3 |
| Progression, 1RM, PRs, exposure, readiness, deload, goal progress, insights | C | Stage 4 |
| Reports, Excel, PDF, backup and restore | C | Stage 5 |
| API contract documents, dashboard data views, backend test suite | C | Stages 4 to 7 |
| Shared vocabulary, calculation specs, test vectors, contract tests | All | Stages 0 to 7 |

Table ownership follows `Architecture v2` section 4: reference and training core to A, body and lifestyle to B, progress and intelligence to C.

Open point: Architecture v2 suggested B could take backup, export and notifications to lighten A. The newer plan gives export to C. This draft gives export and backup to C and reminders to B. Confirm at review.

## Avoiding waiting on each other

- Every contributor builds against the agreed contract, vocabulary and sample data, not against another person's unfinished module.
- Tables owned by B or C that reference A's tables (for example, `exercise_restrictions` referencing `exercises`) rely on the `id uuid` convention. Stage 1 provides stub reference tables so foreign keys can be created before Stage 2 completes.
- Each module has the definition of done in `TECHNICAL_CONTRACT.md` section 14.

## Branches

```
main              tested releases only
 └─ develop       integration branch
     ├─ feature/backend-database
     ├─ feature/backend-workouts
     ├─ feature/backend-lifestyle
     ├─ feature/backend-intelligence
     ├─ feature/backend-reports
     └─ feature/backend-sync
```

Frontend branches (`feature/frontend-foundation`, `feature/mobile-*`, `feature/web-*`) are created after backend sign-off.

## Rules

1. No direct commits to `main` or `develop`. Use pull requests.
2. Every pull request is reviewed by one other contributor. Changes to `docs/TECHNICAL_CONTRACT.md` or `shared/` need all three.
3. Migrations are never edited after they are merged. Add a new migration.
4. Two people never create migrations for the same table in parallel. The owner in the table above creates it; others request changes.
5. Commit messages: short imperative summary, for example `Add workout_sets table with audit trigger`.

## Status note (5 Nov 2026)

Stage 1 was built in a single pass covering all areas of the table above for Stage 1. Ownership for Stages 2 onward is unchanged.
The web client is on hold (D2), so no web work is assigned yet.
