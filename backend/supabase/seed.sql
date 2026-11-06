-- FICTIONAL DEVELOPMENT DATA ONLY. Never run in production.
select pfs_new_version('profile_versions', jsonb_build_object(
  'entity_id', md5('profile')::uuid, 'effective_from', '2026-09-01T00:00:00Z', 'date_of_birth', '2004-03-15',
  'height_cm', 172, 'body_weight_kg', 78.5, 'experience_level', 'intermediate',
  'training_history_notes', 'Sample profile for development.', 'preferred_workout_days', '[1,3,5,6]'::jsonb,
  'preferred_workout_time', '18:00'), 'initial sample profile');

insert into goals (id, type, title, description, target_metric, target_value, target_unit, start_date, intended_duration_days, status) values
  (md5('seed-goal-1')::uuid, 'cutting', 'Slow cut with strength kept', 'Lose fat while keeping lifts steady.', 'body_fat_pct', 15, 'pct', '2026-09-01', 120, 'active'),
  (md5('seed-goal-2')::uuid, 'bulking', 'Lean bulk (finished)', 'Earlier goal, kept for history.', 'body_weight_kg', 80, 'kg', '2026-03-01', 150, 'completed');

insert into reminder_rules (id, kind, label, schedule) values
  (md5('seed-reminder-1')::uuid, 'workout', 'Gym time', '{"type":"weekly","time":"17:30","days":[1,3,5,6]}'),
  (md5('seed-reminder-2')::uuid, 'water', 'Drink water', '{"type":"daily","time":"11:00"}');

update equipment set is_available_at_gym = false where key in ('stairmaster', 'assisted_pullup_machine');
insert into exercises (id, name, is_custom) values (md5('seed-ex-1')::uuid, 'Bench press', false), (md5('seed-ex-2')::uuid, 'Lat pulldown', false);
