# Stage 4 entities, views and functions

Written through `api_apply_operations` (see `stage1_functions.md`) and read through Supabase REST under row level security.
Record classes follow `docs/TECHNICAL_CONTRACT.md` section 10.

## Writable entities

| Entity | Class | Notes |
| --- | --- | --- |
| `exercise_reference` | editable | One per exercise: instructions, form notes, common mistakes, `personal_difficulty` 1 to 5. |
| `media_assets` | editable | Points to a file in the private `media` bucket. `media_type` image or video. |
| `equipment_status_events` | append_only | Event. Status available, occupied or unavailable. |
| `deload_periods` | editable | Dates, status planned, completed or cancelled, reason, what was changed. |
| `goal_progress` | append_only | Manual progress entries for goals the app cannot measure. |
| `milestones` | editable | Title and target value for a goal. |
| `exercises.weight_increment_kg` | (column) | Smallest weight step for the exercise, default 2.5. Used by the next-weight suggestion. |

Read-only for clients (written by the database): `personal_records`, `achievements`.

## Views (REST: `GET /rest/v1/<view>`)

| View | Main columns |
| --- | --- |
| `v_exercise_session_best` | per exercise and session: best estimated 1RM, top weight, max reps, volume |
| `v_exercise_trends` | per exercise: `signal` (improving, plateau, declining, insufficient_data), `change_pct`, sessions considered |
| `v_muscle_recovery_context` | per muscle: last trained, days since, sessions in 28 days, usual gap |
| `v_equipment_status` | per equipment: current status (available, occupied, unavailable) |
| `v_deload_comparison` | per deload: sessions, average volume and fatigue before, during and after |
| `v_goal_progress` | per goal: start, current, `progress_pct`, `progress_status`, source |
| `v_goal_milestones` | per milestone: `is_reached` |
| `v_working_sets` | completed working sets with session facts (the input to the rules) |

## Functions (owner only)

| Function | Returns |
| --- | --- |
| `api_next_targets(p_exercise_ids, p_on = today)` | per exercise: `action` (increase, add_reps, repeat, deload, review, no_history), suggested weight and reps, `reason_codes`, `reasoning` |
| `api_readiness(p_on = today)` | `level`, wellness score, reasons, inputs and context (plan, break day, last session) |
| `api_deload_signals(p_on = today)` | `level` (none, watch, consider_reviewing_deload), reasons, inputs |
| `api_exercise_alternatives(p_exercise_id, p_limit = 5)` | ranked alternatives with score and reason codes |
| `api_weak_point_suggestions()` | per weak muscle: up to 3 exercises, split membership |
| `api_daily_briefing(p_on = today)` | plan, readiness, warnings, suggestions, supplements, hydration, nutrition, steps, reassessment, deload, goals, streak, records, trends, weak points |
| `api_detect_prs(p_device_id, p_session_id)` | re-checks records and achievements for a session (safe to repeat) |
