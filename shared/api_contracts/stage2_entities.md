# Stage 2 entities, views and functions

All entities below are written through `api_apply_operations` (see `stage1_functions.md` for the operation format) and read through
Supabase REST under row level security. Record classes follow `docs/TECHNICAL_CONTRACT.md` section 10.

## Writable entities

| Entity | Class | Notes |
| --- | --- | --- |
| `exercises` | editable | Name unique among live rows (case-insensitive). `category` compound or isolation. |
| `exercise_muscles` | editable | `role` primary, secondary or indirect. One row per exercise and muscle. |
| `exercise_alternatives` | editable | Links only. |
| `workout_templates` | editable | Identity only. `duplicated_from_id` records a duplicate. |
| `template_versions` | versioned | `new_version` only. Payload needs `entity_id`, `name`, may set `id`, `effective_from`, `description`. |
| `template_exercises` | editable | The prescription. Allowed only on an open, unused version, otherwise `immutable_record`. |
| `splits` | editable | `status`: draft, active, inactive, archived. Activating one deactivates the other. |
| `split_versions` | versioned | `new_version` only. `pattern`: fixed_weekly, rolling, custom. |
| `split_days` | editable | Sealed like template exercises. Rest days have no template. |
| `split_day_muscles` | editable | Needs both `split_day_id` and `split_version_id`. Sealed. |
| `schedule_entries` | editable | One per date. `completed` needs `session_id`; `rescheduled` needs `rescheduled_to`; `replaced` needs `replaced_by_activity`. |
| `gym_decisions` | append_only | Event: needs `occurred_at`, `local_date`, `tz_offset_minutes`. |
| `planned_breaks` | editable | Modes full, modified, reduced. Statuses planned, active, ended, cancelled. |
| `break_events` | append_only | Event. |
| `workout_sessions` | editable | Event dates required. Store `template_version_id` and `split_version_id` that applied. `completed` needs `ended_at`. |
| `session_exercises` | editable | Send `template_exercise_id` and the snapshot is filled in. The snapshot cannot be changed later. |
| `sets` | append_only | Event. Warm-up and working sets are numbered separately. Corrections send `base_rev`. |

Read-only for clients (written by the database): `split_status_events`.

## Views (REST: `GET /rest/v1/<view>`)

| View | One row per | Main columns |
| --- | --- | --- |
| `v_session_summary` | session | duration_s (paused time removed), exercises_done, exercises_skipped, working_sets, total_reps, volume_kg, muscles_trained |
| `v_exercise_session_stats` | exercise and session | working_sets, total_reps, volume_kg, top_weight_kg and the previous session's values (`prev_*`) |
| `v_weekly_exercise_volume` | week and exercise | working_sets, total_reps, volume_kg |
| `v_exercise_usage` | exercise and template version | the prescription each version used |
| `v_split_periods` | split activation | start_date, end_date, duration_days, start_reason, end_reason |
| `v_attendance_daily` | schedule entry | is_break_day, is_scheduled_training, is_done, is_missed |
| `v_consistency_weekly` | week | scheduled, completed, missed, break_days, consistency_pct |
| `v_current_streak` | (single row) | current_streak, longest_streak |

## Function

`api_compare_template_versions(p_a uuid, p_b uuid)`: returns `{ added, removed, changed }` prescriptions between two template versions. Owner only.
