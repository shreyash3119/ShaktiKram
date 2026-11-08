# Goals, alternatives and the daily briefing

## Goal progress
`progress = (current - start) / (target - start) x 100`, so it works for goals that go down (cutting) and up (gaining). Reached when the current value is at or past the target.
With a target date, the expected progress is the share of time used (0 to 100). Status: `ahead` (10 or more points above expected), `on_track` (within 10), `behind` (more than 10 below),
`overdue` (past the date, not reached), `no_deadline`, `reached`, or `insufficient_data` (missing values, or start equals target).

Where the current value comes from (`goals.target_metric`):
- `body_weight_kg`, `waist_cm`, `chest_cm`, `arm_cm`, `thigh_cm`: body measurements.
- `body_fat_pct`: readings of the method of the latest reading only (methods are never mixed).
- `est_1rm:<exercise id>`: best estimated 1RM. `max_reps:<exercise id>`: most reps in a working set.
- `consistency_pct`: average weekly consistency of the last 4 weeks (start is 0).
- anything else: manual entries in `goal_progress`.
The start value is the first reading on or after the start date, else the latest before it.

## Alternatives for an exercise
Candidates share at least one primary muscle with the exercise, or are linked as an alternative. Excluded: equipment unavailable or occupied, or an active "avoid" restriction.
Score: 50 x share of primary muscles covered + 10 x share of secondary muscles covered + 15 if same category + 20 if linked as an alternative - 30 if an "uncomfortable" or "modify" restriction applies. Highest first.
Equipment is occupied for 2 hours after an "occupied" event; "unavailable" lasts until an "available" event.

## Weak-point suggestions
For muscles the user rated needs-improvement or high-priority, or gave priority 1, with fewer than 12 direct working sets in the last 28 days (about 3 a week):
up to 3 exercises that train the muscle directly, not blocked by a restriction or unavailable equipment, those not already in the active split first.
A suggestion to consider within the current split, recovery and volume. The rating itself is never calculated.

## Daily briefing
One call that gathers: today's plan and break status, readiness, restriction warnings and next-weight suggestions for the planned exercises,
supplements expected today, hydration, protein plan, steps, reassessment due, deload signal, goals, streak, recent records, and plateau or decline observations.
Each part keeps its own `value_kind`.
