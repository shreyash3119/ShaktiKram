# Strength rules

## Estimated one-rep max
Epley: `weight x (1 + reps / 30)`. One rep gives the weight itself. Only 1 to 12 reps are used; more reps make the estimate unreliable, so there is none. Rounded to 2 decimals. Always `estimated`.

## Next-session suggestion (double progression)
Input: the completed working sets of the exercise's last session (warm-ups excluded), the prescription (rep range, target sets), the smallest
weight step for that exercise (`exercises.weight_increment_kg`, default 2.5), whether a deload is recorded for today, and whether a restriction applies.

The working weight is the most-used weight in that session (the heavier one on a tie). Only sets at that weight count. First matching rule wins:

1. A restriction applies: action `review`, no number. Review or modify before choosing a load.
2. No sets: `no_history`.
3. A deload covers today: `deload`, 90% of the working weight rounded to the weight step, at the bottom of the rep range.
4. Fewer sets than the target at that weight: `repeat`, same weight (`incomplete_sets`).
5. Any set below the bottom of the rep range: `repeat`, same weight, aim for the bottom of the range (`below_rep_range`).
6. Effort very high (any set with 0 reps in reserve, or RPE 9.5 or more): `repeat` (`effort_very_high`).
7. Every set at or above the top of the range: `increase` by one weight step, restart at the bottom of the range (`top_of_range_all_sets`).
8. Otherwise: `add_reps`, same weight, one more rep than the weakest set, capped at the top of the range (`within_range`).

Suggestions are optional and explain themselves. They are never applied automatically.

## Personal records
Computed when a workout is completed, from completed working sets only. A record needs an earlier session of the same exercise: the first session only sets the baseline.
- `max_weight`: heaviest weight, beats every earlier session.
- `est_1rm`: best estimated 1RM, beats every earlier session.
- `best_reps_at_weight`: most reps at a weight, only where that exact weight was used before.
- `session_volume`: weight x reps summed for one exercise in one session, beats every earlier session.
- `workout_volume`: the same for the whole workout (no exercise).
Records are history: a later correction to a set does not delete one. Recomputing is safe (one row per workout, kind and weight).

## Trend and plateau
From the best estimated 1RM of an exercise's last 4 completed sessions within 56 days (oldest first). Fewer than 4: `insufficient_data`.
- `declining`: the latest value is below 95% of the best value in the window.
- `improving`: not declining, and the latest is at least 1.0% above the first.
- `plateau`: otherwise.
An observation, not a verdict.
