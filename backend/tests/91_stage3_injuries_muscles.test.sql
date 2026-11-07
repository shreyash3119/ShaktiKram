-- Stage 3: injuries, pain, restrictions and warnings; muscle assessment, priorities, exposure and reassessment.
begin;
do $$
declare
  sh uuid := md5('body_regions:shoulder')::uuid; lb uuid := md5('body_regions:lower_back')::uuid;
  inj1 uuid := md5('t:inj1')::uuid; inj2 uuid := md5('t:inj2')::uuid; inj3 uuid := md5('t:inj3')::uuid;
  ex_ohp uuid := md5('t:ohp')::uuid; ex_row uuid := md5('t:row')::uuid; ex_curl uuid := md5('t:curl')::uuid;
  rear uuid := md5('muscles:rear_delts')::uuid; side uuid := md5('muscles:side_delts')::uuid; front uuid := md5('muscles:front_delts')::uuid; calves uuid := md5('muscles:calves')::uuid;
  a1 uuid := md5('t:a1')::uuid; a2 uuid := md5('t:a2')::uuid; a3 uuid := md5('t:a3')::uuid;
  ex_rdf uuid := md5('t:rdf')::uuid; ses uuid := md5('t:ses')::uuid; sx uuid := md5('t:sx')::uuid;
  d date := pfs_local_today() - 3; r record; n integer;
begin
  -- injuries and pain
  insert into injuries (id, name, body_region_id, side, start_date, severity, status) values
    (inj1, 'Right shoulder pain', sh, 'right', '2026-10-01', 'moderate', 'active'),
    (inj2, 'Lower back tightness', lb, 'not_applicable', '2026-10-01', 'mild', 'recovering');
  insert into injuries (id, name, body_region_id, side, start_date, severity, status, resolved_on) values
    (inj3, 'Old knee strain', md5('body_regions:knee')::uuid, 'left', '2026-03-01', 'severe', 'resolved', '2026-04-01');
  perform t_expect_error($q$insert into injuries (name, body_region_id, start_date, status) values ('x', (select id from body_regions limit 1), '2026-10-01', 'resolved')$q$, 'ck_injuries_resolved_has_date');
  perform t_expect_error($q$insert into injury_updates (injury_id, occurred_at, local_date, tz_offset_minutes) values ((select id from injuries limit 1), now(), current_date, 0)$q$, 'ck_injury_updates_has_content');
  insert into pain_entries (body_region_id, side, level, injury_id, occurred_at, local_date, tz_offset_minutes) values
    (sh, 'right', 4, inj1, '2026-10-02T12:00:00Z', '2026-10-02', 330),
    (lb, 'not_applicable', 2, inj2, '2026-10-02T12:00:00Z', '2026-10-02', 330);
  insert into pain_entries (body_region_id, side, level, injury_id, effect_on_training, occurred_at, local_date, tz_offset_minutes) values
    (sh, 'right', 7, inj1, 'limited_movement', '2026-10-09T12:00:00Z', '2026-10-09', 330),
    (lb, 'not_applicable', 3, inj2, 'stopped_training', '2026-10-09T12:00:00Z', '2026-10-09', 330);
  perform t_expect_error($q$insert into pain_entries (body_region_id, level, occurred_at, local_date, tz_offset_minutes) values ((select id from body_regions limit 1), 11, now(), current_date, 0)$q$, 'ck_pain_entries_level');
  select * into r from v_injury_summary where injury_id = inj1;
  assert r.latest_pain_level = 7 and r.previous_pain_level = 4 and r.suggest_professional_review, format('severe pain flagged: %s', to_jsonb(r));
  assert not (select suggest_professional_review from v_injury_summary where injury_id = inj2), 'mild stable injury is not flagged';
  assert not (select suggest_professional_review from v_injury_summary where injury_id = inj3), 'resolved injury is not flagged';
  select * into r from v_injury_by_region where body_region_key = 'lower_back';
  assert r.total = 1 and r.recovering_count = 1 and r.stopped_training_entries = 1, format('by region: %s', to_jsonb(r));

  -- muscle assessment: manual ratings, never overwritten, category per level
  insert into muscle_assessments (id, occurred_at, local_date, tz_offset_minutes) values
    (a1, '2026-10-01T12:00:00Z', '2026-10-01', 330), (a2, '2026-10-15T12:00:00Z', '2026-10-15', 330);
  insert into muscle_assessment_items (assessment_id, muscle_id, level) values (a1, rear, 1), (a1, side, 3), (a1, front, 4), (a2, rear, 2), (a2, side, 3);
  perform t_expect_error(format($q$insert into muscle_assessment_items (assessment_id, muscle_id, level) values (%L, %L, 6)$q$, a2, calves), 'ck_muscle_assessment_items_level');
  perform t_expect_error(format($q$insert into muscle_assessment_items (assessment_id, muscle_id, level) values (%L, %L, 3)$q$, a2, rear), 'uq_muscle_assessment_items_alive');
  select * into r from v_muscle_ratings where muscle_id = rear;
  assert r.current_level = 2 and r.previous_level = 1 and r.baseline_level = 1 and r.category = 'needs_improvement'
     and r.assessment_change = 'higher_rating' and r.value_kind = 'user_assessment', format('rear delts: %s', to_jsonb(r));
  assert (select assessment_change from v_muscle_ratings where muscle_id = side) = 'same_rating';
  select * into r from v_muscle_ratings where muscle_id = front;
  assert r.category = 'above_average' and r.assessment_change = 'first_assessment', 'level 4 is above average';
  assert (select current_level from v_muscle_ratings where muscle_id = calves) is null and (select assessment_change from v_muscle_ratings where muscle_id = calves) is null, 'unrated muscle';
  assert (select count(*) from v_muscle_ratings) = 29, 'every muscle is listed';

  -- priorities are versioned
  perform pfs_new_version('muscle_priorities', jsonb_build_object('entity_id', rear, 'effective_from', '2026-10-01T00:00:00Z', 'priority', 1), 'weak point');
  perform pfs_new_version('muscle_priorities', jsonb_build_object('entity_id', rear, 'effective_from', '2026-11-01T00:00:00Z', 'priority', 2), 'improving');
  perform pfs_new_version('muscle_priorities', jsonb_build_object('entity_id', side, 'effective_from', '2026-10-01T00:00:00Z', 'priority', 2), 'maintain');
  select * into r from v_muscle_ratings where muscle_id = rear;
  assert r.current_priority = 2 and r.previous_priority = 1 and r.priority_change = 'lowered', format('priority history: %s', to_jsonb(r));
  assert (select priority_change from v_muscle_ratings where muscle_id = side) = 'new';
  perform t_expect_error(format($q$select pfs_new_version('muscle_priorities', %L::jsonb, 'x')$q$, jsonb_build_object('entity_id', calves, 'effective_from', '2026-10-01T00:00:00Z', 'priority', 4)), 'ck_muscle_priorities_priority');

  -- reassessment reminder: due by interval, not due after a recent assessment
  select * into r from v_reassessment_due;
  assert r.last_assessment_date = '2026-10-15' and r.interval_days = 14 and r.next_due_date = '2026-10-29' and r.is_due = (pfs_local_today() >= '2026-10-29'), format('due: %s', to_jsonb(r));
  insert into muscle_assessments (id, occurred_at, local_date, tz_offset_minutes)
    values (a3, date_trunc('day', now() - interval '5 days') + interval '12 hours', ((date_trunc('day', now() - interval '5 days') + interval '12 hours') at time zone 'UTC' + interval '330 minutes')::date, 330);
  assert not (select is_due from v_reassessment_due), 'recent assessment: not due';

  -- training exposure is separate from the rating
  insert into exercises (id, name, category) values (ex_rdf, 'Reverse pec deck (t)', 'isolation');
  insert into exercise_muscles (exercise_id, muscle_id, role) values (ex_rdf, rear, 'primary'), (ex_rdf, front, 'secondary');
  insert into workout_sessions (id, occurred_at, local_date, tz_offset_minutes, status)
    values (ses, d::timestamp at time zone 'UTC' + interval '12 hours', d, 330, 'in_progress');
  insert into session_exercises (id, session_id, exercise_id, position) values (sx, ses, ex_rdf, 1);
  insert into sets (session_exercise_id, set_number, weight_kg, reps, rpe, occurred_at, local_date, tz_offset_minutes)
    select sx, g, 30, 12, 8, d::timestamp at time zone 'UTC' + interval '12 hours' + (g || ' minutes')::interval, d, 330 from generate_series(1, 3) g;
  select * into r from v_muscle_exposure_weekly where muscle_id = rear and week_start = date_trunc('week', d)::date;
  assert r.direct_sets = 3 and r.indirect_sets = 0 and r.training_days = 1 and r.avg_rpe = 8.0, format('rear exposure: %s', to_jsonb(r));
  select * into r from v_muscle_exposure_weekly where muscle_id = front and week_start = date_trunc('week', d)::date;
  assert r.direct_sets = 0 and r.indirect_sets = 3, 'secondary role counts as indirect';
  select * into r from v_weak_point_attention where muscle_id = rear;
  assert r.direct_sets_28d = 3 and r.direct_training_days_28d = 1 and r.category = 'needs_improvement', format('weak point attention: %s', to_jsonb(r));
  assert not exists (select 1 from v_weak_point_attention where muscle_id in (front, side)), 'only muscles the user marked weak are listed';

  -- restrictions
  insert into exercises (id, name) values (ex_ohp, 'Overhead press (t)'), (ex_row, 'Barbell row (t)'), (ex_curl, 'Curl (t)');
  insert into exercise_restrictions (injury_id, exercise_id, kind, source, active_from) values (inj1, ex_ohp, 'avoid', 'professional', '2026-10-01');
  insert into exercise_restrictions (injury_id, exercise_id, kind, active_from) values (inj3, ex_row, 'uncomfortable', '2026-03-01');
  insert into exercise_restrictions (exercise_id, kind, active_from, active_to) values (ex_curl, 'modify', '2026-10-01', '2026-10-05');
  perform t_expect_error($q$insert into exercise_restrictions (kind) values ('avoid')$q$, 'ck_exercise_restrictions_target');
end $$;

-- warnings through the API (owner only)
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-00000000000a', true);
set local role authenticated;
select api_claim_owner();
do $$
declare w jsonb; ids uuid[] := array[md5('t:ohp')::uuid, md5('t:row')::uuid, md5('t:curl')::uuid];
begin
  w := api_restriction_warnings(ids, '2026-10-10') -> 'data' -> 'warnings';
  assert jsonb_array_length(w) = 1 and w -> 0 ->> 'kind' = 'avoid' and w -> 0 ->> 'suggestion' = 'review_or_modify_before_training', 'active injury restriction flagged: ' || w::text;
  w := api_restriction_warnings(ids, '2026-10-03') -> 'data' -> 'warnings';
  assert jsonb_array_length(w) = 2, 'a restriction inside its dates is flagged; one tied to a resolved injury is not: ' || w::text;
  perform set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-0000-0000-00000000000b', true);
  perform t_expect_error(format('select api_restriction_warnings(%L::uuid[])', ids), 'unauthorized');
end $$;
rollback;
