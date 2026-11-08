-- Stage 4 / personal records and achievements, written by the database when a workout is completed.
-- Deferred triggers run once at commit, so a whole sync request (session, exercises, sets, completion) is seen as it ends up.
-- A record needs an earlier session of the same exercise: the first session only sets the baseline.

create function pfs_add_pr(p_exercise uuid, p_kind text, p_value numeric, p_weight numeric, p_reps integer, p_prev numeric, p_session uuid, p_set uuid, p_date date)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare rc integer;
begin
  insert into personal_records (exercise_id, kind, value, weight_kg, reps, previous_value, session_id, set_id, achieved_on)
  values (p_exercise, p_kind, p_value, p_weight, p_reps, p_prev, p_session, p_set, p_date)
  on conflict (session_id, kind, (coalesce(exercise_id, '00000000-0000-0000-0000-000000000000'::uuid)), (coalesce(case when kind = 'best_reps_at_weight' then weight_kg end, -1)))
  do update set value = excluded.value, weight_kg = excluded.weight_kg, reps = excluded.reps, previous_value = excluded.previous_value, set_id = excluded.set_id
  where excluded.value > personal_records.value;
  get diagnostics rc = row_count;
  return rc;
end $$;

create function pfs_detect_prs(p_session_id uuid) returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s workout_sessions%rowtype; n integer := 0; r record; w record;
  prev_sessions integer; prev_top numeric; prev_e1rm numeric; prev_vol numeric; prev_reps integer; prev_hist integer; total numeric; prev_total numeric; sid uuid;
begin
  if pfs_restore_allowed() then return 0; end if;
  select * into s from workout_sessions where id = p_session_id and deleted_at is null;
  if not found or s.status <> 'completed' then return 0; end if;
  for r in select exercise_id, max(weight_kg) as top_weight, max(pfs_e1rm(weight_kg, reps)) as best_e1rm, sum(weight_kg * reps) as volume
             from v_working_sets where session_id = p_session_id group by exercise_id loop
    select count(distinct session_id), max(weight_kg), max(pfs_e1rm(weight_kg, reps)) into prev_sessions, prev_top, prev_e1rm
      from v_working_sets where exercise_id = r.exercise_id and session_occurred_at < s.occurred_at and session_status = 'completed';
    continue when prev_sessions < 1;
    if r.top_weight > prev_top then
      select set_id into sid from v_working_sets where session_id = p_session_id and exercise_id = r.exercise_id and weight_kg = r.top_weight order by reps desc limit 1;
      n := n + pfs_add_pr(r.exercise_id, 'max_weight', r.top_weight, r.top_weight, null, prev_top, p_session_id, sid, s.local_date);
    end if;
    if r.best_e1rm is not null and prev_e1rm is not null and r.best_e1rm > prev_e1rm then
      select set_id into sid from v_working_sets where session_id = p_session_id and exercise_id = r.exercise_id and pfs_e1rm(weight_kg, reps) = r.best_e1rm limit 1;
      n := n + pfs_add_pr(r.exercise_id, 'est_1rm', r.best_e1rm, null, null, prev_e1rm, p_session_id, sid, s.local_date);
    end if;
    select max(v) into prev_vol from (select sum(weight_kg * reps) v from v_working_sets where exercise_id = r.exercise_id and session_occurred_at < s.occurred_at and session_status = 'completed' group by session_id) q;
    if r.volume > prev_vol then n := n + pfs_add_pr(r.exercise_id, 'session_volume', r.volume, null, null, prev_vol, p_session_id, null, s.local_date); end if;
    for w in select weight_kg, max(reps) as reps from v_working_sets where session_id = p_session_id and exercise_id = r.exercise_id group by weight_kg loop
      select max(reps), count(*) into prev_reps, prev_hist from v_working_sets where exercise_id = r.exercise_id and weight_kg = w.weight_kg and session_occurred_at < s.occurred_at and session_status = 'completed';
      if prev_hist > 0 and w.reps > prev_reps then
        select set_id into sid from v_working_sets where session_id = p_session_id and exercise_id = r.exercise_id and weight_kg = w.weight_kg and reps = w.reps limit 1;
        n := n + pfs_add_pr(r.exercise_id, 'best_reps_at_weight', w.reps, w.weight_kg, w.reps, prev_reps, p_session_id, sid, s.local_date);
      end if;
    end loop;
  end loop;
  select sum(weight_kg * reps) into total from v_working_sets where session_id = p_session_id;
  select max(v), count(*) into prev_total, prev_sessions from (select sum(weight_kg * reps) v from v_working_sets where session_occurred_at < s.occurred_at and session_status = 'completed' group by session_id) q;
  if prev_sessions >= 1 and total > prev_total then n := n + pfs_add_pr(null, 'workout_volume', total, null, null, prev_total, p_session_id, null, s.local_date); end if;
  return n;
end $$;

create function pfs_detect_achievements(p_session_id uuid) returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare s workout_sessions%rowtype; total integer; t integer; n integer := 0; rc integer; sess record; strk integer;
begin
  if pfs_restore_allowed() then return 0; end if;
  select * into s from workout_sessions where id = p_session_id and deleted_at is null;
  if not found or s.status <> 'completed' then return 0; end if;
  select count(*) into total from workout_sessions where deleted_at is null and status = 'completed';
  foreach t in array array[1, 10, 25, 50, 100, 250, 500] loop
    continue when total < t;
    select id, local_date into sess from workout_sessions where deleted_at is null and status = 'completed' order by occurred_at, id offset t - 1 limit 1;
    insert into achievements (kind, threshold, title, achieved_on, supporting_table, supporting_record_id)
    values ('workouts_completed', t, case when t = 1 then 'First workout completed' else t || ' workouts completed' end, sess.local_date, 'workout_sessions', sess.id) on conflict do nothing;
    get diagnostics rc = row_count; n := n + rc;
  end loop;
  select current_streak into strk from v_current_streak;
  foreach t in array array[5, 10, 20, 50] loop
    continue when coalesce(strk, 0) < t;
    insert into achievements (kind, threshold, title, achieved_on, supporting_table, supporting_record_id)
    values ('streak', t, t || ' scheduled sessions in a row', s.local_date, 'workout_sessions', s.id) on conflict do nothing;
    get diagnostics rc = row_count; n := n + rc;
  end loop;
  return n;
end $$;

create function pfs_session_completed_trigger() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_session uuid := case tg_table_name when 'workout_sessions' then (to_jsonb(new) ->> 'id')::uuid
  else (select se.session_id from session_exercises se where se.id = (to_jsonb(new) ->> 'session_exercise_id')::uuid) end;
begin
  if pfs_restore_allowed() or v_session is null then return null; end if;
  perform pfs_detect_prs(v_session);
  perform pfs_detect_achievements(v_session);
  return null;
end $$;
create constraint trigger y_session_completed after insert or update on workout_sessions deferrable initially deferred
  for each row when (new.status = 'completed') execute function pfs_session_completed_trigger();
create constraint trigger y_set_detect after insert or update on sets deferrable initially deferred
  for each row execute function pfs_session_completed_trigger();
