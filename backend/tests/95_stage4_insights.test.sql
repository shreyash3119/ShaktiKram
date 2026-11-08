-- Stage 4: suggestions, trends, readiness, deload signals, goals, alternatives, weak points and the daily briefing.
begin;
create function t_work(p_ex uuid, p_days_ago int, p_sets jsonb) returns uuid language plpgsql as $$
declare d date := pfs_local_today() - p_days_ago; s uuid := gen_random_uuid(); se uuid := gen_random_uuid(); e jsonb; n int := 0;
begin
  insert into workout_sessions (id, occurred_at, ended_at, local_date, tz_offset_minutes, status)
  values (s, (d::text || 'T12:00:00Z')::timestamptz, (d::text || 'T13:00:00Z')::timestamptz, d, 330, 'completed');
  insert into session_exercises (id, session_id, exercise_id, position) values (se, s, p_ex, 1);
  for e in select * from jsonb_array_elements(p_sets) loop
    n := n + 1;
    insert into sets (session_exercise_id, set_number, weight_kg, reps, rir, rpe, occurred_at, local_date, tz_offset_minutes)
    values (se, n, (e ->> 'w')::numeric, (e ->> 'r')::int, (e ->> 'rir')::smallint, (e ->> 'rpe')::numeric, (d::text || 'T12:30:00Z')::timestamptz + (n || ' minutes')::interval, d, 330);
  end loop;
  return s;
end $$;
create function t_meas(p_days_ago int, p_type text, p_value numeric) returns void language plpgsql as $$
declare d date := pfs_local_today() - p_days_ago;
begin
  insert into body_measurements (occurred_at, local_date, tz_offset_minutes, measurement_type, value) values ((d::text || 'T06:00:00Z')::timestamptz, d, 330, p_type, p_value);
end $$;
create function t_ex(p_key text, p_name text, p_cat text, p_primary text, p_secondary text default null, p_equipment text default null) returns uuid language plpgsql as $$
declare id uuid := md5('t95:' || p_key)::uuid;
begin
  insert into exercises (id, name, category, equipment_id) values (id, p_name, p_cat, case when p_equipment is null then null else md5('equipment:' || p_equipment)::uuid end);
  insert into exercise_muscles (exercise_id, muscle_id, role) values (id, md5('muscles:' || p_primary)::uuid, 'primary');
  if p_secondary is not null then insert into exercise_muscles (exercise_id, muscle_id, role) values (id, md5('muscles:' || p_secondary)::uuid, 'secondary'); end if;
  return id;
end $$;

-- ===== setup (as the database owner) =====
do $$
declare
  e1 uuid := t_ex('bench', 'Bench (t95)', 'compound', 'middle_chest', 'front_delts'); e2 uuid := t_ex('curl', 'Curl (t95)', 'isolation', 'biceps'); e3 uuid := t_ex('ohp', 'OHP (t95)', 'compound', 'front_delts');
  e4 uuid := t_ex('decl', 'Decline-ish (t95)', 'compound', 'quadriceps'); e5 uuid := t_ex('plat', 'Plateau-ish (t95)', 'compound', 'hamstrings'); e6 uuid := t_ex('impr', 'Improving-ish (t95)', 'compound', 'lats');
  tpl uuid := md5('t95:tpl')::uuid; tv uuid := md5('t95:tv')::uuid; r record;
begin
  insert into workout_templates (id) values (tpl);
  perform pfs_new_version('template_versions', jsonb_build_object('id', tv, 'entity_id', tpl, 'name', 'T95', 'effective_from', '2026-10-01T00:00:00Z'), 'setup');
  insert into template_exercises (template_version_id, exercise_id, position, target_sets, rep_min, rep_max) values (tv, e1, 1, 3, 8, 12), (tv, e2, 2, 3, 8, 12), (tv, e3, 3, 3, 8, 12);
  perform t_work(e1, 1, '[{"w":60,"r":12,"rir":2},{"w":60,"r":12,"rir":2},{"w":60,"r":12,"rir":2}]');
  perform t_work(e3, 1, '[{"w":40,"r":12},{"w":40,"r":12},{"w":40,"r":12}]');
  insert into exercise_restrictions (exercise_id, kind, source, active_from) values (e3, 'avoid', 'self', pfs_local_today() - 5);
  -- trends: declining, plateau, improving (best estimated 1RM per session)
  perform t_work(e4, 21, '[{"w":100,"r":5}]'); perform t_work(e4, 14, '[{"w":105,"r":5}]'); perform t_work(e4, 7, '[{"w":107.5,"r":5}]'); perform t_work(e4, 1, '[{"w":100,"r":5}]');
  perform t_work(e5, 22, '[{"w":60,"r":10}]'); perform t_work(e5, 15, '[{"w":60,"r":10}]'); perform t_work(e5, 8, '[{"w":60,"r":10}]'); perform t_work(e5, 2, '[{"w":60,"r":10}]');
  perform t_work(e6, 25, '[{"w":50,"r":10}]'); perform t_work(e6, 18, '[{"w":52.5,"r":10}]'); perform t_work(e6, 11, '[{"w":55,"r":10}]'); perform t_work(e6, 4, '[{"w":57.5,"r":10}]');
  assert (select signal from v_exercise_trends where exercise_id = e4) = 'declining', 'latest session well below the best';
  assert (select signal from v_exercise_trends where exercise_id = e5) = 'plateau' and (select signal from v_exercise_trends where exercise_id = e6) = 'improving';
  select * into r from v_exercise_trends where exercise_id = e6;
  assert r.sessions_considered = 4 and r.change_pct = 15.0 and r.value_kind = 'observation', format('improving: %s', to_jsonb(r));
  assert (select signal from v_exercise_trends where exercise_id = e1) = 'insufficient_data', 'one session is not a trend';
  -- recovery context
  assert (select days_since from v_muscle_recovery_context where muscle_key = 'quadriceps') = 1 and (select training_days_28d from v_muscle_recovery_context where muscle_key = 'quadriceps') = 4, 'recovery context';
  assert (select last_trained_on from v_muscle_recovery_context where muscle_key = 'calves') is null;

  -- goals: weight (on track), manual reps, strength
  insert into goals (id, type, title, target_metric, target_value, start_date, target_date, status) values
    (md5('t95:gw')::uuid, 'cutting', 'Cut', 'body_weight_kg', 76, pfs_local_today() - 30, pfs_local_today() + 30, 'active'),
    (md5('t95:gm')::uuid, 'exercise_performance', 'Pull-ups', 'pull_up_reps', 12, pfs_local_today() - 20, null, 'active'),
    (md5('t95:ge')::uuid, 'strength', 'Lat strength', 'est_1rm:' || e6, 80, pfs_local_today() - 30, null, 'active');
  perform t_meas(29, 'weight', 80); perform t_meas(1, 'weight', 78);
  insert into goal_progress (goal_id, local_date, value) values (md5('t95:gm')::uuid, pfs_local_today() - 19, 5), (md5('t95:gm')::uuid, pfs_local_today() - 1, 8);
  insert into milestones (goal_id, title, target_value) values (md5('t95:gw')::uuid, 'Reach 78', 78), (md5('t95:gw')::uuid, 'Reach 77', 77);
  select * into r from v_goal_progress where goal_id = md5('t95:gw')::uuid;
  assert r.progress_pct = 50.0 and r.progress_status = 'on_track' and r.start_value = 80 and r.current_value = 78 and r.source = 'body_measurements', format('weight goal: %s', to_jsonb(r));
  select * into r from v_goal_progress where goal_id = md5('t95:gm')::uuid;
  assert r.progress_pct = 42.9 and r.progress_status = 'no_deadline' and r.source = 'goal_progress', format('manual goal: %s', to_jsonb(r));
  select * into r from v_goal_progress where goal_id = md5('t95:ge')::uuid;
  assert r.progress_pct = 75.0 and r.source = 'sets', format('strength goal: %s', to_jsonb(r));
  assert (select is_reached from v_goal_milestones where title = 'Reach 78') and not (select is_reached from v_goal_milestones where title = 'Reach 77'), 'milestones';

  -- readiness inputs, fatigue history and an old first session
  insert into daily_checkins (local_date, energy, sleep_quality, soreness, fatigue, motivation, stress) values (pfs_local_today(), 4, 4, 2, 2, 4, 2);
  insert into sleep_logs (local_date, duration_s) values (pfs_local_today(), 27000);
  insert into daily_checkins (local_date, fatigue) select pfs_local_today() - g, 5 from generate_series(2, 9) g;
  perform t_work(e5, 60, '[{"w":60,"r":10}]');
end $$;

-- ===== owner calls =====
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-00000000000a', true);
set local role authenticated;
select api_claim_owner();
do $$
declare
  e1 uuid := md5('t95:bench')::uuid; e2 uuid := md5('t95:curl')::uuid; e3 uuid := md5('t95:ohp')::uuid; r jsonb; x jsonb;
begin
  -- next-session suggestions
  r := api_next_targets(array[e1, e2, e3]) -> 'data' -> 'suggestions';
  select e into x from jsonb_array_elements(r) e where e ->> 'exercise_id' = e1::text;
  assert x ->> 'action' = 'increase' and (x ->> 'suggested_weight_kg')::numeric = 62.5 and x ->> 'prescription_source' = 'current_template' and x ->> 'value_kind' = 'suggestion', 'bench: ' || x::text;
  select e into x from jsonb_array_elements(r) e where e ->> 'exercise_id' = e2::text;
  assert x ->> 'action' = 'no_history', 'curl: ' || x::text;
  select e into x from jsonb_array_elements(r) e where e ->> 'exercise_id' = e3::text;
  assert x ->> 'action' = 'review' and x -> 'suggested_weight_kg' = 'null'::jsonb, 'a restriction means review, no number: ' || x::text;

  -- readiness
  r := api_readiness() -> 'data';
  assert r ->> 'level' = 'proceed' and (r ->> 'wellness_score')::numeric = 4.0 and (r -> 'context' ->> 'is_break_day')::boolean = false and r ->> 'value_kind' = 'suggestion', 'readiness: ' || r::text;
  assert r -> 'context' ->> 'days_since_last_session' = '1', 'last session was yesterday';
  assert (api_readiness(pfs_local_today() - 12) -> 'data' ->> 'level') = 'no_checkin', 'a day without a check-in';

  -- deload signals: an old first session and high fatigue in 8 of the last 9 check-ins
  r := api_deload_signals() -> 'data';
  assert r ->> 'level' = 'consider_reviewing_deload' and r -> 'reason_codes' = '["long_block", "persistent_fatigue"]'::jsonb, 'deload: ' || r::text;
end $$;
reset role;

-- a recent deload changes the suggestion; recent pain changes the readiness
insert into deload_periods (start_date, end_date, status, reason) values (pfs_local_today() - 1, pfs_local_today() + 5, 'planned', 'test');
insert into pain_entries (body_region_id, side, level, occurred_at, local_date, tz_offset_minutes)
  values (md5('body_regions:shoulder')::uuid, 'right', 8, (pfs_local_today()::text || 'T12:00:00Z')::timestamptz, pfs_local_today(), 330);
set local role authenticated;
do $$
declare r jsonb; x jsonb; e1 uuid := md5('t95:bench')::uuid;
begin
  r := api_next_targets(array[e1]) -> 'data' -> 'suggestions' -> 0;
  assert r ->> 'action' = 'deload' and (r ->> 'suggested_weight_kg')::numeric = 55, 'deload week: ' || r::text;
  r := api_readiness() -> 'data';
  assert r ->> 'level' = 'review' and r -> 'reason_codes' = '["high_pain"]'::jsonb, 'pain: ' || r::text;
  assert (select count(*) from v_deload_comparison) = 1 and (select sessions_before from v_deload_comparison) >= 1, 'deload comparison';
end $$;
reset role;
update deload_periods set status = 'cancelled';

-- ===== alternatives, weak points, daily briefing =====
do $$
declare
  af uuid := t_ex('af', 'Cable fly (t95)', 'isolation', 'middle_chest'); ap uuid := t_ex('ap', 'Pec deck (t95)', 'isolation', 'middle_chest', null, 'pec_deck_machine');
  ad uuid := t_ex('ad', 'Dumbbell fly (t95)', 'isolation', 'middle_chest'); ab uuid := t_ex('ab', 'Barbell bench (t95b)', 'compound', 'middle_chest', 'front_delts');
  am uuid := t_ex('am', 'Chest press machine (t95)', 'compound', 'middle_chest', null, 'chest_press_machine'); ax uuid := t_ex('ax', 'Push-up (t95)', 'compound', 'middle_chest');
  ar uuid := t_ex('ar', 'Row (t95)', 'compound', 'lats');
  rd1 uuid := t_ex('rd1', 'Reverse pec deck (t95)', 'isolation', 'rear_delts'); rd2 uuid := t_ex('rd2', 'Face pull (t95)', 'isolation', 'rear_delts');
  rd3 uuid := t_ex('rd3', 'Bent-over fly (t95)', 'isolation', 'rear_delts'); rd4 uuid := t_ex('rd4', 'Rear delt cable (t95)', 'isolation', 'rear_delts');
  tplf uuid := md5('t95:tplf')::uuid; tvf uuid := md5('t95:tvf')::uuid; spl uuid := md5('t95:spl')::uuid; svf uuid := md5('t95:svf')::uuid; a1 uuid := md5('t95:a1')::uuid; tv uuid := md5('t95:tv')::uuid;
begin
  insert into exercise_alternatives (exercise_id, alternative_id) values (af, ad);
  insert into equipment_status_events (equipment_id, status, occurred_at, local_date, tz_offset_minutes)
    values (md5('equipment:chest_press_machine')::uuid, 'unavailable', now(), ((now() at time zone 'UTC') + interval '330 minutes')::date, 330);
  insert into exercise_restrictions (exercise_id, kind, active_from) values (ax, 'avoid', pfs_local_today() - 1), (rd4, 'avoid', pfs_local_today() - 1);
  assert (select current_status from v_equipment_status where key = 'chest_press_machine') = 'unavailable' and (select current_status from v_equipment_status where key = 'pec_deck_machine') = 'available';
  -- weak point: rear delts rated 1; Face pull is part of the active split
  insert into muscle_assessments (id, occurred_at, local_date, tz_offset_minutes) values (a1, now(), ((now() at time zone 'UTC') + interval '330 minutes')::date, 330);
  insert into muscle_assessment_items (assessment_id, muscle_id, level) values (a1, md5('muscles:rear_delts')::uuid, 1);
  insert into workout_templates (id) values (tplf);
  perform pfs_new_version('template_versions', jsonb_build_object('id', tvf, 'entity_id', tplf, 'name', 'Rear day', 'effective_from', '2026-10-01T00:00:00Z'), 'setup');
  insert into template_exercises (template_version_id, exercise_id, position) values (tvf, rd2, 1);
  insert into splits (id, status) values (spl, 'active');
  perform pfs_new_version('split_versions', jsonb_build_object('id', svf, 'entity_id', spl, 'name', 'S95', 'effective_from', '2026-10-01T00:00:00Z'), 'setup');
  insert into split_days (split_version_id, position, label, template_id) values (svf, 1, 'Rear', tplf);
  -- supplement, water, steps, schedule for the briefing
  insert into supplements (id, name) values (md5('t95:sup')::uuid, 'Creatine (t95)');
  perform pfs_new_version('supplement_phases', jsonb_build_object('id', md5('t95:sph')::uuid, 'entity_id', md5('t95:sup')::uuid, 'effective_from', '2026-10-01T00:00:00Z', 'status', 'active', 'times_per_day', 1), 'start');
  insert into supplement_logs (supplement_id, phase_id, outcome, quantity, occurred_at, local_date, tz_offset_minutes)
    values (md5('t95:sup')::uuid, md5('t95:sph')::uuid, 'taken', 5, (pfs_local_today()::text || 'T12:00:00Z')::timestamptz, pfs_local_today(), 330);
  perform pfs_new_version('personal_targets', jsonb_build_object('entity_id', md5('t95:tg')::uuid, 'effective_from', '2026-10-01T00:00:00Z', 'water_ml', 2500, 'step_target', 10000), 'setup');
  insert into water_logs (amount_ml, occurred_at, local_date, tz_offset_minutes) values (500, (pfs_local_today()::text || 'T12:00:00Z')::timestamptz, pfs_local_today(), 330);
  insert into daily_steps (local_date, steps) values (pfs_local_today(), 6000);
  insert into schedule_entries (local_date, status, template_version_id) values (pfs_local_today(), 'planned', tv);
end $$;
set local role authenticated;
do $$
declare r jsonb; x jsonb; k text; af uuid := md5('t95:af')::uuid;
begin
  r := api_exercise_alternatives(af) -> 'data' -> 'alternatives';
  assert (select array_agg(e ->> 'exercise_name' order by ord) from jsonb_array_elements(r) with ordinality t(e, ord)) = array['Dumbbell fly (t95)', 'Pec deck (t95)', 'Barbell bench (t95b)', 'Bench (t95)'], 'alternatives ranked, ties by name: ' || r::text;
  assert (r -> 0 ->> 'score')::numeric = 85.0 and (r -> 1 ->> 'score')::numeric = 65.0 and (r -> 2 ->> 'score')::numeric = 50.0 and r -> 0 -> 'reason_codes' ? 'linked_alternative', 'scores and reasons';
  assert jsonb_array_length(api_exercise_alternatives(af, 1) -> 'data' -> 'alternatives') = 1, 'limit';

  r := api_weak_point_suggestions() -> 'data' -> 'muscles';
  assert jsonb_array_length(r) = 1 and r -> 0 ->> 'muscle_key' = 'rear_delts', 'only the muscle marked weak: ' || r::text;
  assert (select array_agg(e ->> 'exercise_name' order by ord) from jsonb_array_elements(r -> 0 -> 'suggestions') with ordinality t(e, ord)) = array['Bent-over fly (t95)', 'Reverse pec deck (t95)', 'Face pull (t95)'], 'weak point suggestions: ' || (r -> 0 -> 'suggestions')::text;
  assert (r -> 0 -> 'suggestions' -> 2 ->> 'in_current_split')::boolean and not (r -> 0 -> 'suggestions' -> 0 ->> 'in_current_split')::boolean, 'split membership';

  r := api_daily_briefing() -> 'data';
  foreach k in array array['plan', 'readiness', 'restriction_warnings', 'next_targets', 'supplements_today', 'hydration', 'nutrition', 'steps', 'reassessment', 'deload', 'goals', 'streak', 'recent_records', 'trends', 'weak_points'] loop
    assert r ? k, 'briefing has ' || k;
  end loop;
  assert (r -> 'plan' ->> 'planned_exercises')::int = 3 and r -> 'plan' ->> 'template_name' = 'T95' and r -> 'plan' ->> 'active_split' = 'S95' and not (r -> 'plan' ->> 'is_break_day')::boolean, 'plan: ' || (r -> 'plan')::text;
  assert r -> 'readiness' ->> 'level' = 'review', 'pain from earlier: ' || (r -> 'readiness')::text;
  assert jsonb_array_length(r -> 'restriction_warnings') = 1 and jsonb_array_length(r -> 'next_targets') = 3, 'warnings and suggestions for the planned exercises';
  assert (r -> 'supplements_today' -> 0 ->> 'taken_today')::int = 1 and (r -> 'hydration' ->> 'total_ml')::int = 500 and (r ->> 'water_target_ml')::int = 2500, 'supplement and water';
  assert (r -> 'steps' ->> 'steps')::int = 6000 and (r -> 'steps' ->> 'target')::int = 10000, 'steps against the target';
  assert r -> 'deload' ->> 'level' = 'consider_reviewing_deload' and not (r -> 'deload' ? 'inputs'), 'deload signal';
  assert r -> 'goals' ->> 'on_track' = '1' and r -> 'goals' ->> 'no_deadline' = '2', 'goals by status: ' || (r -> 'goals')::text;
  assert exists (select 1 from jsonb_array_elements(r -> 'trends') e where e ->> 'signal' = 'declining') and exists (select 1 from jsonb_array_elements(r -> 'trends') e where e ->> 'signal' = 'plateau'), 'trends: ' || (r -> 'trends')::text;
  assert jsonb_array_length(r -> 'weak_points') = 1, 'weak points';
  perform set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-0000-0000-00000000000b', true);
  perform t_expect_error('select api_daily_briefing()', 'unauthorized');
  perform t_expect_error('select api_next_targets(array[gen_random_uuid()])', 'unauthorized');
end $$;
rollback;
