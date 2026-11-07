-- Stage 2: the whole workout lifecycle through the write API, history preservation, sealing, comparison.
begin;
create function t_op(p_seq int, p_entity text, p_action text, p_id uuid, p_payload jsonb default '{}'::jsonb, p_base bigint default null) returns jsonb language sql as $$
  select jsonb_strip_nulls(jsonb_build_object('op_id', gen_random_uuid(), 'seq', p_seq, 'entity', p_entity, 'action', p_action, 'record_id', p_id, 'base_rev', p_base, 'payload', p_payload)) $$;
create function t_try(p_ops jsonb) returns jsonb language sql as $$
  select api_apply_operations('d1111111-0000-0000-0000-000000000001', gen_random_uuid(), p_ops) -> 'data' -> 'results' $$;
create function t_run(p_ops jsonb) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  r := t_try(p_ops);
  if exists (select 1 from jsonb_array_elements(r) e where e ->> 'result' <> 'applied') then raise exception 'operation failed: %', r; end if;
  return r;
end $$;
grant execute on function t_op(int, text, text, uuid, jsonb, bigint), t_try(jsonb), t_run(jsonb) to public;

select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-00000000000a', true);
set local role authenticated;
select api_claim_owner();
select api_register_device('d1111111-0000-0000-0000-000000000001', 'Test phone', 'mobile');

do $$
declare
  ex_bench uuid := md5('t:bench')::uuid; ex_fly uuid := md5('t:fly')::uuid;
  tpl uuid := md5('t:tpl')::uuid; tv1 uuid := md5('t:tv1')::uuid; tv2 uuid := md5('t:tv2')::uuid;
  te1 uuid := md5('t:te1')::uuid; te2 uuid := md5('t:te2')::uuid; te1b uuid := md5('t:te1b')::uuid; te2b uuid := md5('t:te2b')::uuid;
  sp1 uuid := md5('t:sp1')::uuid; sv1 uuid := md5('t:sv1')::uuid; sd1 uuid := md5('t:sd1')::uuid; sd2 uuid := md5('t:sd2')::uuid;
  sp2 uuid := md5('t:sp2')::uuid; sv2 uuid := md5('t:sv2')::uuid;
  se_a uuid := md5('t:se_a')::uuid; se_b uuid := md5('t:se_b')::uuid;
  ses1 uuid := md5('t:ses1')::uuid; ses2 uuid := md5('t:ses2')::uuid;
  sx1 uuid := md5('t:sx1')::uuid; sx2 uuid := md5('t:sx2')::uuid; sx3 uuid := md5('t:sx3')::uuid;
  mc uuid := md5('muscles:middle_chest')::uuid; fd uuid := md5('muscles:front_delts')::uuid;
  r jsonb; sm record; st record; n integer;
begin
  -- 1. plan: exercises, muscle mapping, template with prescriptions, split with days
  perform t_run(jsonb_build_array(
    t_op(1, 'exercises', 'upsert', ex_bench, jsonb_build_object('name', 'Bench press (t)', 'category', 'compound')),
    t_op(2, 'exercises', 'upsert', ex_fly, jsonb_build_object('name', 'Cable fly (t)', 'category', 'isolation')),
    t_op(3, 'exercise_muscles', 'upsert', md5('t:em1')::uuid, jsonb_build_object('exercise_id', ex_bench, 'muscle_id', mc, 'role', 'primary')),
    t_op(4, 'exercise_muscles', 'upsert', md5('t:em2')::uuid, jsonb_build_object('exercise_id', ex_bench, 'muscle_id', fd, 'role', 'secondary')),
    t_op(5, 'exercise_muscles', 'upsert', md5('t:em3')::uuid, jsonb_build_object('exercise_id', ex_fly, 'muscle_id', mc, 'role', 'primary')),
    t_op(6, 'workout_templates', 'upsert', tpl),
    t_op(7, 'template_versions', 'new_version', null, jsonb_build_object('id', tv1, 'entity_id', tpl, 'name', 'Chest day', 'effective_from', '2026-10-01T00:00:00Z')),
    t_op(8, 'template_exercises', 'upsert', te1, jsonb_build_object('template_version_id', tv1, 'exercise_id', ex_bench, 'position', 1, 'target_sets', 3, 'rep_min', 10, 'rep_max', 12, 'start_weight_kg', 60, 'rest_s', 120, 'rir_target', 2)),
    t_op(9, 'template_exercises', 'upsert', te2, jsonb_build_object('template_version_id', tv1, 'exercise_id', ex_fly, 'position', 2, 'target_sets', 3, 'rep_min', 12, 'rep_max', 15)),
    t_op(10, 'splits', 'upsert', sp1, jsonb_build_object('status', 'draft')),
    t_op(11, 'split_versions', 'new_version', null, jsonb_build_object('id', sv1, 'entity_id', sp1, 'name', '4 day', 'pattern', 'fixed_weekly', 'effective_from', '2026-10-01T00:00:00Z')),
    t_op(12, 'split_days', 'upsert', sd1, jsonb_build_object('split_version_id', sv1, 'position', 1, 'label', 'Chest', 'is_rest', false, 'template_id', tpl)),
    t_op(13, 'split_days', 'upsert', sd2, jsonb_build_object('split_version_id', sv1, 'position', 2, 'label', 'Rest', 'is_rest', true)),
    t_op(14, 'split_day_muscles', 'upsert', md5('t:sdm1')::uuid, jsonb_build_object('split_day_id', sd1, 'split_version_id', sv1, 'muscle_id', mc))));
  assert (select count(*) from template_exercises where template_version_id = tv1) = 2, 'prescriptions saved';

  -- 2. activate the split, schedule two days, run a session with a skipped exercise
  perform t_run(jsonb_build_array(
    t_op(1, 'splits', 'upsert', sp1, jsonb_build_object('status', 'active'), (select rev from splits where id = sp1)),
    t_op(2, 'schedule_entries', 'upsert', se_a, jsonb_build_object('local_date', '2026-10-05', 'is_rest_day', false, 'split_version_id', sv1, 'split_day_id', sd1, 'template_version_id', tv1)),
    t_op(3, 'schedule_entries', 'upsert', se_b, jsonb_build_object('local_date', '2026-10-06', 'is_rest_day', true, 'split_version_id', sv1, 'split_day_id', sd2)),
    t_op(4, 'workout_sessions', 'upsert', ses1, jsonb_build_object('occurred_at', '2026-10-05T12:30:00Z', 'local_date', '2026-10-05', 'tz_offset_minutes', 330,
         'name', 'Chest day', 'status', 'in_progress', 'schedule_entry_id', se_a, 'split_version_id', sv1, 'split_day_id', sd1, 'template_version_id', tv1, 'paused_seconds', 300)),
    t_op(5, 'session_exercises', 'upsert', sx1, jsonb_build_object('session_id', ses1, 'exercise_id', ex_bench, 'position', 1, 'status', 'done', 'template_exercise_id', te1)),
    t_op(6, 'session_exercises', 'upsert', sx2, jsonb_build_object('session_id', ses1, 'exercise_id', ex_fly, 'position', 2, 'status', 'skipped', 'skip_reason', 'machine busy', 'template_exercise_id', te2)),
    t_op(7, 'sets', 'upsert', md5('t:set0')::uuid, jsonb_build_object('session_exercise_id', sx1, 'set_number', 1, 'set_type', 'warmup', 'weight_kg', 40, 'reps', 10, 'occurred_at', '2026-10-05T12:35:00Z', 'local_date', '2026-10-05', 'tz_offset_minutes', 330)),
    t_op(8, 'sets', 'upsert', md5('t:set1')::uuid, jsonb_build_object('session_exercise_id', sx1, 'set_number', 1, 'weight_kg', 60, 'reps', 10, 'rir', 2, 'rpe', 8, 'occurred_at', '2026-10-05T12:40:00Z', 'local_date', '2026-10-05', 'tz_offset_minutes', 330)),
    t_op(9, 'sets', 'upsert', md5('t:set2')::uuid, jsonb_build_object('session_exercise_id', sx1, 'set_number', 2, 'weight_kg', 60, 'reps', 10, 'occurred_at', '2026-10-05T12:45:00Z', 'local_date', '2026-10-05', 'tz_offset_minutes', 330)),
    t_op(10, 'sets', 'upsert', md5('t:set3')::uuid, jsonb_build_object('session_exercise_id', sx1, 'set_number', 3, 'weight_kg', 60, 'reps', 8, 'occurred_at', '2026-10-05T12:50:00Z', 'local_date', '2026-10-05', 'tz_offset_minutes', 330))));
  perform t_run(jsonb_build_array(
    t_op(1, 'workout_sessions', 'upsert', ses1, jsonb_build_object('status', 'completed', 'ended_at', '2026-10-05T13:30:00Z'), (select rev from workout_sessions where id = ses1)),
    t_op(2, 'schedule_entries', 'upsert', se_a, jsonb_build_object('status', 'completed', 'session_id', ses1), (select rev from schedule_entries where id = se_a))));

  select * into sm from v_session_summary where session_id = ses1;
  assert sm.duration_s = 3300, 'duration excludes paused time: ' || sm.duration_s;
  assert sm.exercises_done = 1 and sm.exercises_skipped = 1, 'done and skipped exercises';
  assert sm.working_sets = 3 and sm.total_reps = 28 and sm.volume_kg = 1680, 'warm-up sets excluded from volume';
  assert sm.muscles_trained = array['middle_chest'], 'muscles trained from primary mapping';
  assert (select prescription_snapshot ->> 'rep_max' from session_exercises where id = sx1) = '12', 'snapshot copied from the template';
  assert (select prescription_snapshot ->> 'template_version_id' from session_exercises where id = sx1) = tv1::text;
  assert (select prescription_snapshot ->> 'exercise_name' from session_exercises where id = sx1) = 'Bench press (t)';
  assert (select count(*) from split_status_events where split_id = sp1 and status = 'active') = 1, 'split activation recorded';
  assert (select is_done from v_attendance_daily where local_date = '2026-10-05'), 'completed day counts as done';

  -- 3. a used version is sealed: changes need a new version
  r := t_try(jsonb_build_array(
    t_op(1, 'template_exercises', 'upsert', md5('t:te3')::uuid, jsonb_build_object('template_version_id', tv1, 'exercise_id', ex_fly, 'position', 3)),
    t_op(2, 'template_exercises', 'upsert', te1, jsonb_build_object('target_sets', 5), (select rev from template_exercises where id = te1)),
    t_op(3, 'split_days', 'delete', sd1)));
  assert (select array_agg(e ->> 'error_code') from jsonb_array_elements(r) e) = array['immutable_record', 'immutable_record', 'immutable_record'], 'sealed version refuses changes: ' || r::text;

  -- 4. change the rep range: new version, old session keeps its prescription
  perform t_run(jsonb_build_array(
    t_op(1, 'template_versions', 'new_version', null, jsonb_build_object('id', tv2, 'entity_id', tpl, 'name', 'Chest day', 'effective_from', '2026-11-01T00:00:00Z')),
    t_op(2, 'template_exercises', 'upsert', te1b, jsonb_build_object('template_version_id', tv2, 'exercise_id', ex_bench, 'position', 1, 'target_sets', 4, 'rep_min', 8, 'rep_max', 10, 'start_weight_kg', 62.5, 'rest_s', 150, 'rir_target', 2)),
    t_op(3, 'template_exercises', 'upsert', te2b, jsonb_build_object('template_version_id', tv2, 'exercise_id', ex_fly, 'position', 2, 'target_sets', 3, 'rep_min', 12, 'rep_max', 15))));
  assert (select effective_to from template_versions where id = tv1) = '2026-11-01T00:00:00Z', 'old version closed';
  assert (select prescription_snapshot ->> 'rep_max' from session_exercises where id = sx1) = '12', 'old session still shows old rep range';
  assert (select target_sets from template_exercises where id = te1) = 3, 'old prescription row unchanged';
  r := t_try(jsonb_build_array(t_op(1, 'session_exercises', 'upsert', sx1, jsonb_build_object('prescription_snapshot', '{"rep_max": 99}'::jsonb), (select rev from session_exercises where id = sx1))));
  assert r -> 0 ->> 'error_code' = 'immutable_record', 'snapshot cannot be rewritten';

  perform t_run(jsonb_build_array(
    t_op(1, 'workout_sessions', 'upsert', ses2, jsonb_build_object('occurred_at', '2026-11-02T12:30:00Z', 'ended_at', '2026-11-02T13:20:00Z', 'local_date', '2026-11-02', 'tz_offset_minutes', 330,
         'name', 'Chest day', 'status', 'completed', 'template_version_id', tv2)),
    t_op(2, 'session_exercises', 'upsert', sx3, jsonb_build_object('session_id', ses2, 'exercise_id', ex_bench, 'position', 1, 'status', 'done', 'template_exercise_id', te1b)),
    t_op(3, 'sets', 'upsert', md5('t:set4')::uuid, jsonb_build_object('session_exercise_id', sx3, 'set_number', 1, 'weight_kg', 62.5, 'reps', 8, 'occurred_at', '2026-11-02T12:40:00Z', 'local_date', '2026-11-02', 'tz_offset_minutes', 330)),
    t_op(4, 'sets', 'upsert', md5('t:set5')::uuid, jsonb_build_object('session_exercise_id', sx3, 'set_number', 2, 'weight_kg', 62.5, 'reps', 8, 'occurred_at', '2026-11-02T12:45:00Z', 'local_date', '2026-11-02', 'tz_offset_minutes', 330)),
    t_op(5, 'sets', 'upsert', md5('t:set6')::uuid, jsonb_build_object('session_exercise_id', sx3, 'set_number', 3, 'weight_kg', 62.5, 'reps', 8, 'occurred_at', '2026-11-02T12:50:00Z', 'local_date', '2026-11-02', 'tz_offset_minutes', 330)),
    t_op(6, 'sets', 'upsert', md5('t:set7')::uuid, jsonb_build_object('session_exercise_id', sx3, 'set_number', 4, 'weight_kg', 62.5, 'reps', 8, 'occurred_at', '2026-11-02T12:55:00Z', 'local_date', '2026-11-02', 'tz_offset_minutes', 330))));
  assert (select prescription_snapshot ->> 'rep_max' from session_exercises where id = sx3) = '10', 'new session uses new rep range';

  -- comparison with the previous session of the same exercise
  select * into st from v_exercise_session_stats where session_id = ses2 and exercise_id = ex_bench;
  assert st.volume_kg = 2000 and st.working_sets = 4 and st.prev_volume_kg = 1680 and st.prev_top_weight_kg = 60 and st.prev_session_id = ses1, 'previous session comparison';
  assert (select volume_kg from v_weekly_exercise_volume where exercise_id = ex_bench and week_start = '2026-10-05') = 1680, 'weekly volume';
  assert (select count(*) from v_exercise_usage where exercise_id = ex_bench) = 2, 'exercise usage across template versions';
  r := api_compare_template_versions(tv1, tv2) -> 'data';
  assert jsonb_array_length(r -> 'changed') = 1 and jsonb_array_length(r -> 'added') = 0 and jsonb_array_length(r -> 'removed') = 0, 'only the bench prescription changed: ' || r::text;
  assert r -> 'changed' -> 0 -> 'from' ->> 'target_sets' = '3' and r -> 'changed' -> 0 -> 'to' ->> 'target_sets' = '4';

  -- 5. switching splits: one active at a time, periods recorded
  perform t_run(jsonb_build_array(
    t_op(1, 'splits', 'upsert', sp2, jsonb_build_object('status', 'draft')),
    t_op(2, 'split_versions', 'new_version', null, jsonb_build_object('id', sv2, 'entity_id', sp2, 'name', '3 day', 'pattern', 'rolling', 'cycle_length_days', 4, 'effective_from', '2026-11-01T00:00:00Z'))));
  perform t_run(jsonb_build_array(t_op(1, 'splits', 'upsert', sp2, jsonb_build_object('status', 'active'), (select rev from splits where id = sp2))));
  assert (select status from splits where id = sp1) = 'inactive' and (select count(*) from splits where status = 'active') = 1, 'activating a split deactivates the other';
  assert (select count(*) from split_status_events where split_id = sp1 and status = 'inactive') = 1, 'deactivation recorded';
  assert (select end_date from v_split_periods where split_id = sp1) is not null and (select name from v_split_periods where split_id = sp1) = '4 day', 'split period closed with its name';

  -- 6. database rules reach the API
  r := t_try(jsonb_build_array(
    t_op(1, 'schedule_entries', 'upsert', md5('t:bad1')::uuid, jsonb_build_object('local_date', '2026-12-01', 'status', 'completed')),
    t_op(2, 'sets', 'upsert', md5('t:bad2')::uuid, jsonb_build_object('session_exercise_id', sx3, 'set_number', 9, 'rpe', 7.3, 'occurred_at', '2026-11-02T13:00:00Z', 'local_date', '2026-11-02', 'tz_offset_minutes', 330)),
    t_op(3, 'planned_breaks', 'upsert', md5('t:bad3')::uuid, jsonb_build_object('title', 'x', 'start_date', '2026-12-10', 'end_date', '2026-12-01')),
    t_op(4, 'sets', 'upsert', md5('t:bad4')::uuid, jsonb_build_object('session_exercise_id', sx3, 'set_number', 8, 'occurred_at', '2026-11-02T13:00:00Z', 'local_date', '2026-11-03', 'tz_offset_minutes', 330)),
    t_op(5, 'workout_sessions', 'upsert', md5('t:bad5')::uuid, jsonb_build_object('occurred_at', '2026-11-02T13:00:00Z', 'local_date', '2026-11-02', 'tz_offset_minutes', 330, 'status', 'completed'))));
  assert (select array_agg(e ->> 'error_code') from jsonb_array_elements(r) e) = array['validation_failed', 'validation_failed', 'validation_failed', 'validation_failed', 'validation_failed'], 'rule violations rejected: ' || r::text;
end $$;
reset role;
do $$ begin
  assert exists (select 1 from audit_log where table_name = 'template_versions' and action = 'version_close'), 'version close audited';
  assert exists (select 1 from audit_log where table_name = 'splits' and action = 'update' and after = '{"status": "inactive"}'::jsonb), 'split deactivation audited';
end $$;
rollback;
