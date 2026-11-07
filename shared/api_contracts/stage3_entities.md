# Stage 3 entities, views and functions

All entities below are written through `api_apply_operations` (see `stage1_functions.md` for the operation format) and read through
Supabase REST under row level security. Record classes follow `docs/TECHNICAL_CONTRACT.md` section 10.

## Writable entities

| Entity | Class | Notes |
| --- | --- | --- |
| `daily_checkins` | editable | One per `local_date`. Scores 1 to 5 and all optional. Direction of each score is in `scales.json`. |
| `sleep_logs` | editable | `duration_s` required; sleep and wake times optional. Naps set `is_nap`. |
| `daily_steps` | editable | One per `local_date`. |
| `cardio_sessions` | append_only | Event. `custom` activity needs `custom_activity`. Speed in m/s, distance in m. |
| `body_measurements` | append_only | Event. One row per reading. `body_fat` needs `method`; `custom` needs `custom_label` and `custom_unit`. Units: kg, percent, cm. |
| `injuries` | editable | `resolved` needs `resolved_on`. Never deleted on resolve. |
| `injury_updates` | append_only | Event. Needs a note, severity or status. |
| `pain_entries` | append_only | Event. `level` 0 to 10. Separate from soreness. |
| `exercise_restrictions` | editable | Needs `exercise_id` or `movement`. Only `exercise_id` restrictions raise warnings. |
| `muscle_assessments` | append_only | Event. One assessment per entry, never overwritten. |
| `muscle_assessment_items` | append_only | `level` 1 to 5, one per muscle per assessment. |
| `muscle_priorities` | versioned | `new_version` only. `entity_id` is the muscle id. `priority` 1 to 3. |
| `weak_point_events` | append_only | Event: identified, exercise_added, reassessed. |
| `supplements` | editable | Name unique among live rows. |
| `supplement_phases` | versioned | `new_version` only. `entity_id` is the supplement id. Status active, paused or stopped. |
| `supplement_logs` | append_only | Event. Outcome taken, missed or skipped. |
| `meals`, `meal_ingredients`, `meal_components` | editable | Library. Nutrition is optional. |
| `meal_plan_entries` | editable | `replaced` needs `replaced_by_meal_id`. |
| `personal_targets` | versioned | `new_version` only. One set of targets: protein, calories, water, steps. |
| `water_logs` | append_only | Event. |

## Views (REST: `GET /rest/v1/<view>`)

| View | Main columns |
| --- | --- |
| `v_body_composition` | per body-fat reading: method, body_fat_pct, weight_kg, fat_mass_kg, lean_mass_kg (null without a same-day weight), value_kind |
| `v_measurement_latest` | latest reading per type (and method, label, side) |
| `v_sleep_weekly`, `v_steps_weekly`, `v_cardio_weekly` | weekly averages and totals |
| `v_meal_nutrition` | per meal: nutrition, `nutrition_source` (meal, ingredients, components), `is_estimate` |
| `v_daily_nutrition` | planned and eaten protein and calories, target of that day, percent of target |
| `v_daily_hydration` | total_ml, target_ml, pct_of_target |
| `v_supplement_adherence`, `v_supplement_summary`, `v_supplement_limit_flags` | adherence per active phase, lifecycle summary, days over the recorded limit |
| `v_muscle_ratings` | current, previous and baseline level, category, `assessment_change`, priority and `priority_change` |
| `v_reassessment_due` | last date, next due date, `is_due`, days overdue |
| `v_muscle_exposure_weekly` | direct and indirect sets, training days, average effort per muscle and week |
| `v_weak_point_attention` | weak muscles with their direct work in the last 28 days |
| `v_injury_summary`, `v_injury_by_region` | status, latest pain, `suggest_professional_review`; counts by body region |

## Functions

- `api_restriction_warnings(p_exercise_ids uuid[], p_on date = today)`: restrictions that apply to the planned exercises.
- `api_due_reminders(p_from timestamptz, p_to timestamptz)`: reminders firing in a window of at most 8 days.
- `pfs_muscle_category(level)`, `pfs_target_on(date)`, `pfs_tz()`, `pfs_local_date(ts)`: helpers, callable by the owner.

Both `api_` functions are owner only.
