-- Stage 4: personal records and achievements are written by the database when workouts are completed.
begin;
create function t_sess(p_id uuid, p_date date) returns void language plpgsql as $$
begin
  insert into workout_sessions (id, occurred_at, ended_at, local_date, tz_offset_minutes, status)
  values (p_id, (p_date::text || 'T12:00:00Z')::timestamptz, (p_date::text || 'T13:00:00Z')::timestamptz, p_date, 330, 'completed');
end $$;
create function t_set(p_se uuid, p_n int, p_w numeric, p_r int, p_date date) returns void language plpgsql as $$
begin
  insert into sets (session_exercise_id, set_number, weight_kg, reps, occurred_at, local_date, tz_offset_minutes)
  values (p_se, p_n, p_w, p_r, (p_date::text || 'T12:30:00Z')::timestamptz + (p_n || ' minutes')::interval, p_date, 330);
end $$;
do $$
declare
  ex uuid := md5('t94:bench')::uuid; s1 uuid := md5('t94:s1')::uuid; s2 uuid := md5('t94:s2')::uuid; s3 uuid := md5('t94:s3')::uuid;
  se1 uuid := md5('t94:se1')::uuid; se2 uuid := md5('t94:se2')::uuid; se3 uuid := md5('t94:se3')::uuid; r record; i int; sx uuid;
begin
  insert into exercises (id, name, category) values (ex, 'Bench (t94)', 'compound');
  perform t_sess(s1, '2026-10-01'); insert into session_exercises (id, session_id, exercise_id, position) values (se1, s1, ex, 1);
  perform t_set(se1, 1, 60, 10, '2026-10-01'); perform t_set(se1, 2, 60, 10, '2026-10-01'); perform t_set(se1, 3, 60, 8, '2026-10-01');
  perform t_sess(s2, '2026-10-08'); insert into session_exercises (id, session_id, exercise_id, position) values (se2, s2, ex, 1);
  for i in 1..3 loop perform t_set(se2, i, 62.5, 8, '2026-10-08'); end loop;
  perform t_sess(s3, '2026-10-15'); insert into session_exercises (id, session_id, exercise_id, position) values (se3, s3, ex, 1);
  perform t_set(se3, 1, 62.5, 10, '2026-10-15'); perform t_set(se3, 2, 62.5, 9, '2026-10-15'); perform t_set(se3, 3, 62.5, 8, '2026-10-15');
  set constraints all immediate;
  set constraints all deferred;

  assert (select count(*) from personal_records where session_id = s1) = 0, 'the first session only sets the baseline';
  select * into r from personal_records where session_id = s2;
  assert (select count(*) from personal_records where session_id = s2) = 1 and r.kind = 'max_weight' and r.value = 62.5 and r.previous_value = 60 and r.exercise_id = ex, format('session 2: %s', to_jsonb(r));
  assert (select array_agg(kind order by kind) from personal_records where session_id = s3) = array['best_reps_at_weight', 'est_1rm', 'session_volume', 'workout_volume'], 'session 3 records';
  assert (select value from personal_records where session_id = s3 and kind = 'est_1rm') = 83.33, 'estimated 1RM record';
  assert (select value from personal_records where session_id = s3 and kind = 'session_volume') = 1687.50;
  select * into r from personal_records where session_id = s3 and kind = 'best_reps_at_weight';
  assert r.value = 10 and r.previous_value = 8 and r.weight_kg = 62.5 and r.set_id is not null, 'best reps at a weight used before';
  assert (select exercise_id from personal_records where session_id = s3 and kind = 'workout_volume') is null, 'workout volume belongs to no exercise';
  assert pfs_detect_prs(s3) = 0, 'detection is safe to repeat';
  assert (select count(*) from personal_records) = 5;

  -- achievements
  select * into r from achievements where kind = 'workouts_completed' and threshold = 1;
  assert r.achieved_on = '2026-10-01' and r.supporting_record_id = s1 and r.title = 'First workout completed', 'first workout';
  assert (select count(*) from achievements) = 1;

  -- a later correction keeps one record per workout and updates it
  update sets set reps = 11 where session_exercise_id = se3 and set_number = 1;
  set constraints all immediate; set constraints all deferred;
  assert (select count(*) from personal_records where session_id = s3) = 4, 'still one record per kind';
  assert (select value from personal_records where session_id = s3 and kind = 'best_reps_at_weight') = 11 and (select value from personal_records where session_id = s3 and kind = 'est_1rm') = 85.42, 'record follows the corrected set';

  -- ten workouts and five scheduled sessions in a row
  for i in 16..22 loop
    sx := gen_random_uuid(); perform t_sess(sx, ('2026-10-' || i)::date);
    if i <= 20 then insert into schedule_entries (local_date, status, session_id) values (('2026-10-' || i)::date, 'completed', sx); end if;
  end loop;
  set constraints all immediate; set constraints all deferred;
  select * into r from achievements where kind = 'workouts_completed' and threshold = 10;
  assert r.achieved_on = '2026-10-22' and r.title = '10 workouts completed', 'tenth workout';
  assert exists (select 1 from achievements where kind = 'streak' and threshold = 5), 'five scheduled sessions in a row';
  assert not exists (select 1 from achievements where kind = 'workouts_completed' and threshold = 25);
end $$;

-- clients cannot write records or achievements; the check happens through the API
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-00000000000a', true);
set local role authenticated;
select api_claim_owner();
select api_register_device('d1111111-0000-0000-0000-000000000001', 'Test phone', 'mobile');
do $$
declare r jsonb;
begin
  r := api_apply_operations('d1111111-0000-0000-0000-000000000001', gen_random_uuid(), jsonb_build_array(
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 1, 'entity', 'personal_records', 'action', 'upsert', 'record_id', gen_random_uuid(), 'payload', '{}'::jsonb),
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 2, 'entity', 'achievements', 'action', 'delete', 'record_id', gen_random_uuid()))) -> 'data' -> 'results';
  assert r -> 0 ->> 'error_code' = 'validation_failed' and r -> 1 ->> 'error_code' = 'validation_failed', 'records and achievements are read-only for clients: ' || r::text;
  r := api_detect_prs('d1111111-0000-0000-0000-000000000001', md5('t94:s3')::uuid) -> 'data';
  assert (r ->> 'records_changed')::int = 0, 're-checking changes nothing: ' || r::text;
end $$;
rollback;
