-- FICTIONAL SAMPLE DATA: 12 weeks (Monday 2026-08-03 to Sunday 2026-10-25) for tests, reports and demos. Never load into production.
-- Deterministic: no random numbers. Load it after the migrations and seed.sql.
do $$
declare
  d0 constant date := '2026-08-03'; d date; wk int; dow int; n int; i int;
  ex_bench uuid := md5('sample:ex:bench')::uuid; ex_incl uuid := md5('sample:ex:incl')::uuid; ex_row uuid := md5('sample:ex:row')::uuid;
  ex_rdf uuid := md5('sample:ex:rdf')::uuid; ex_sq uuid := md5('sample:ex:sq')::uuid; ex_curl uuid := md5('sample:ex:curl')::uuid;
  t_push uuid := md5('sample:t:push')::uuid; t_pull uuid := md5('sample:t:pull')::uuid; t_legs uuid := md5('sample:t:legs')::uuid;
  tv_push1 uuid := md5('sample:tv:push1')::uuid; tv_push2 uuid := md5('sample:tv:push2')::uuid; tv_pull uuid := md5('sample:tv:pull')::uuid; tv_legs uuid := md5('sample:tv:legs')::uuid;
  sp uuid := md5('sample:split')::uuid; sv uuid := md5('sample:sv')::uuid;
  sd_push uuid := md5('sample:sd:1')::uuid; sd_pull uuid := md5('sample:sd:3')::uuid; sd_legs uuid := md5('sample:sd:5')::uuid;
  kind text; tv uuid; sd uuid; entry uuid; ses uuid; sx uuid; te record; w numeric; inc numeric; reps int; k int;
  sup uuid := md5('sample:sup')::uuid; ph1 uuid := md5('sample:ph1')::uuid; ph2 uuid := md5('sample:ph2')::uuid; ph3 uuid := md5('sample:ph3')::uuid; ph uuid;
  m1 uuid := md5('sample:meal1')::uuid; m2 uuid := md5('sample:meal2')::uuid; m3 uuid := md5('sample:meal3')::uuid;
  inj uuid := md5('sample:inj')::uuid; brk uuid := md5('sample:break')::uuid; a1 uuid; a2 uuid; a3 uuid; ts text;
begin
  -- exercises and the muscles they train
  insert into exercises (id, name, category, equipment_id, weight_increment_kg) values
    (ex_bench, 'Barbell bench press', 'compound', md5('equipment:barbell')::uuid, 2.5), (ex_incl, 'Incline dumbbell press', 'compound', md5('equipment:dumbbell')::uuid, 2.0),
    (ex_row, 'Seated cable row', 'compound', md5('equipment:seated_row_machine')::uuid, 2.5), (ex_rdf, 'Reverse pec deck', 'isolation', md5('equipment:pec_deck_machine')::uuid, 1.25),
    (ex_sq, 'Back squat', 'compound', md5('equipment:squat_rack')::uuid, 2.5), (ex_curl, 'Dumbbell curl', 'isolation', md5('equipment:dumbbell')::uuid, 1.0);
  insert into exercise_muscles (exercise_id, muscle_id, role) values
    (ex_bench, md5('muscles:middle_chest')::uuid, 'primary'), (ex_bench, md5('muscles:front_delts')::uuid, 'secondary'), (ex_bench, md5('muscles:triceps_lateral_head')::uuid, 'secondary'),
    (ex_incl, md5('muscles:upper_chest')::uuid, 'primary'), (ex_incl, md5('muscles:front_delts')::uuid, 'secondary'),
    (ex_row, md5('muscles:lats')::uuid, 'primary'), (ex_row, md5('muscles:rhomboids')::uuid, 'secondary'), (ex_row, md5('muscles:biceps')::uuid, 'secondary'),
    (ex_rdf, md5('muscles:rear_delts')::uuid, 'primary'), (ex_rdf, md5('muscles:middle_traps')::uuid, 'secondary'),
    (ex_sq, md5('muscles:quadriceps')::uuid, 'primary'), (ex_sq, md5('muscles:glutes')::uuid, 'secondary'), (ex_curl, md5('muscles:biceps')::uuid, 'primary');
  insert into exercise_reference (exercise_id, instructions, form_notes, personal_difficulty) values (ex_bench, 'Lie flat, bar over the chest.', 'Shoulder blades pulled back; controlled lowering.', 3);

  -- templates (the push template changes its prescription in week 9) and a split
  insert into workout_templates (id) values (t_push), (t_pull), (t_legs);
  perform pfs_new_version('template_versions', jsonb_build_object('id', tv_push1, 'entity_id', t_push, 'name', 'Push', 'effective_from', '2026-08-03T00:00:00Z'), 'start');
  insert into template_exercises (id, template_version_id, exercise_id, position, target_sets, rep_min, rep_max, start_weight_kg, rest_s, rir_target) values
    (md5('sample:te:push1:1')::uuid, tv_push1, ex_bench, 1, 3, 8, 12, 60, 120, 2), (md5('sample:te:push1:2')::uuid, tv_push1, ex_incl, 2, 3, 8, 12, 20, 90, 2);
  perform pfs_new_version('template_versions', jsonb_build_object('id', tv_push2, 'entity_id', t_push, 'name', 'Push', 'effective_from', '2026-09-28T00:00:00Z'), 'strength block');
  insert into template_exercises (id, template_version_id, exercise_id, position, target_sets, rep_min, rep_max, start_weight_kg, rest_s, rir_target) values
    (md5('sample:te:push2:1')::uuid, tv_push2, ex_bench, 1, 4, 6, 10, 70, 150, 2), (md5('sample:te:push2:2')::uuid, tv_push2, ex_incl, 2, 3, 8, 12, 26, 90, 2);
  perform pfs_new_version('template_versions', jsonb_build_object('id', tv_pull, 'entity_id', t_pull, 'name', 'Pull', 'effective_from', '2026-08-03T00:00:00Z'), 'start');
  insert into template_exercises (id, template_version_id, exercise_id, position, target_sets, rep_min, rep_max, start_weight_kg, rest_s) values
    (md5('sample:te:pull:1')::uuid, tv_pull, ex_row, 1, 3, 8, 12, 50, 90), (md5('sample:te:pull:2')::uuid, tv_pull, ex_rdf, 2, 3, 12, 15, 20, 60);
  perform pfs_new_version('template_versions', jsonb_build_object('id', tv_legs, 'entity_id', t_legs, 'name', 'Legs and arms', 'effective_from', '2026-08-03T00:00:00Z'), 'start');
  insert into template_exercises (id, template_version_id, exercise_id, position, target_sets, rep_min, rep_max, start_weight_kg, rest_s) values
    (md5('sample:te:legs:1')::uuid, tv_legs, ex_sq, 1, 3, 6, 10, 80, 150), (md5('sample:te:legs:2')::uuid, tv_legs, ex_curl, 2, 3, 10, 12, 12, 60);
  insert into splits (id, status) values (sp, 'active');
  update split_status_events set occurred_at = '2026-08-03T06:00:00Z', local_date = '2026-08-03', tz_offset_minutes = 330 where split_id = sp;
  perform pfs_new_version('split_versions', jsonb_build_object('id', sv, 'entity_id', sp, 'name', 'Push Pull Legs', 'pattern', 'fixed_weekly', 'effective_from', '2026-08-03T00:00:00Z'), 'start');
  insert into split_days (id, split_version_id, position, label, is_rest, template_id) values
    (sd_push, sv, 1, 'Push', false, t_push), (md5('sample:sd:2')::uuid, sv, 2, 'Rest', true, null), (sd_pull, sv, 3, 'Pull', false, t_pull),
    (md5('sample:sd:4')::uuid, sv, 4, 'Rest', true, null), (sd_legs, sv, 5, 'Legs and arms', false, t_legs), (md5('sample:sd:6')::uuid, sv, 6, 'Rest', true, null), (md5('sample:sd:7')::uuid, sv, 7, 'Rest', true, null);
  insert into split_day_muscles (split_day_id, split_version_id, muscle_id) values
    (sd_push, sv, md5('muscles:middle_chest')::uuid), (sd_pull, sv, md5('muscles:lats')::uuid), (sd_legs, sv, md5('muscles:quadriceps')::uuid);

  -- an exam break and a deload
  insert into planned_breaks (id, title, start_date, end_date, reason, mode, status) values (brk, 'Exam week', '2026-09-14', '2026-09-20', 'exams_study', 'full', 'ended');
  insert into break_events (break_id, event, occurred_at, local_date, tz_offset_minutes) values
    (brk, 'started', '2026-09-14T03:00:00Z', '2026-09-14', 330), (brk, 'ended', '2026-09-20T15:00:00Z', '2026-09-20', 330);
  insert into deload_periods (start_date, end_date, status, reason, changes) values ('2026-09-28', '2026-10-04', 'completed', 'Planned lighter week', 'Weights reduced by about 10 percent.');

  -- training: three sessions a week, a skipped day in week 3 and week 6, no gym in the exam week, a lighter week 9
  for wk in 0..11 loop
    for dow in 1..5 by 2 loop
      d := d0 + wk * 7 + (dow - 1);
      kind := case dow when 1 then 'push' when 3 then 'pull' else 'legs' end;
      tv := case kind when 'push' then case when wk >= 8 then tv_push2 else tv_push1 end when 'pull' then tv_pull else tv_legs end;
      sd := case kind when 'push' then sd_push when 'pull' then sd_pull else sd_legs end;
      entry := md5('sample:entry:' || d)::uuid;
      if wk = 6 then
        insert into schedule_entries (id, local_date, split_version_id, split_day_id, template_version_id, status, reason) values (entry, d, sv, sd, tv, 'skipped', 'exams');
      elsif (wk = 2 and dow = 3) or (wk = 5 and dow = 5) then
        insert into schedule_entries (id, local_date, split_version_id, split_day_id, template_version_id, status, reason) values (entry, d, sv, sd, tv, 'skipped', 'missed');
      else
        insert into schedule_entries (id, local_date, split_version_id, split_day_id, template_version_id, status) values (entry, d, sv, sd, tv, 'planned');
        ses := md5('sample:ses:' || d)::uuid; ts := d::text;
        insert into workout_sessions (id, occurred_at, ended_at, local_date, tz_offset_minutes, name, status, schedule_entry_id, split_version_id, split_day_id, template_version_id, paused_seconds)
        values (ses, (ts || 'T12:30:00Z')::timestamptz, (ts || 'T13:35:00Z')::timestamptz, d, 330, initcap(kind), 'completed', entry, sv, sd, tv, 120);
        for te in select t.id, t.exercise_id, t.position, t.target_sets, t.rep_min, t.rep_max, t.start_weight_kg, t.rir_target, e.weight_increment_kg as inc
                    from template_exercises t join exercises e on e.id = t.exercise_id where t.template_version_id = tv order by t.position loop
          sx := md5('sample:sx:' || d || te.position)::uuid;
          insert into session_exercises (id, session_id, exercise_id, position, template_exercise_id) values (sx, ses, te.exercise_id, te.position, te.id);
          k := floor((wk - case when kind = 'push' and wk >= 8 then 8 else 0 end) / 2.0);
          w := te.start_weight_kg + te.inc * k;
          if wk = 8 then w := round(w * 0.9 / te.inc) * te.inc; end if;
          for n in 1..te.target_sets loop
            reps := greatest(te.rep_min, te.rep_max - (n - 1) - (1 - wk % 2));
            insert into sets (id, session_exercise_id, set_number, set_type, weight_kg, reps, rir, occurred_at, local_date, tz_offset_minutes)
            values (md5('sample:set:' || d || te.position || n)::uuid, sx, n, 'working', w, reps, case when n = te.target_sets then 1 else 2 end,
                    (ts || 'T12:40:00Z')::timestamptz + ((te.position * 10 + n * 3) || ' minutes')::interval, d, 330);
          end loop;
        end loop;
        update schedule_entries set status = 'completed', session_id = ses where id = entry;
      end if;
    end loop;
  end loop;

  -- daily records
  for i in 0..83 loop
    d := d0 + i; ts := d::text; dow := extract(isodow from d); wk := i / 7;
    insert into daily_checkins (local_date, energy, sleep_quality, soreness, fatigue, motivation, stress, pain_flag) values (d,
      3 + abs(hashtext('e' || ts)) % 3, 3 + abs(hashtext('q' || ts)) % 3, 1 + abs(hashtext('s' || ts)) % 3,
      case when d between '2026-09-21' and '2026-09-27' then 4 + abs(hashtext('f' || ts)) % 2 else 1 + abs(hashtext('f' || ts)) % 3 end,
      3 + abs(hashtext('m' || ts)) % 3, 1 + abs(hashtext('t' || ts)) % 3, d between '2026-09-01' and '2026-09-12');
    insert into sleep_logs (local_date, duration_s, quality) values (d, 23400 + abs(hashtext('sl' || ts)) % 7200, 3 + abs(hashtext('sq' || ts)) % 3);
    insert into daily_steps (local_date, steps, target_steps) values (d, 6000 + abs(hashtext('st' || ts)) % 6000, 10000);
    insert into water_logs (amount_ml, occurred_at, local_date, tz_offset_minutes) values (1500 + abs(hashtext('w' || ts)) % 1500, (ts || 'T10:00:00Z')::timestamptz, d, 330);
    if dow = 1 then
      insert into body_measurements (occurred_at, local_date, tz_offset_minutes, measurement_type, value) values ((ts || 'T01:30:00Z')::timestamptz, d, 330, 'weight', round(80.0 - 0.15 * wk + ((abs(hashtext('wt' || ts)) % 5) - 2) * 0.1, 1));
      if wk % 2 = 0 then insert into body_measurements (occurred_at, local_date, tz_offset_minutes, measurement_type, value, method) values ((ts || 'T01:35:00Z')::timestamptz, d, 330, 'body_fat', round(20.0 - 0.12 * wk, 1), 'smart_scale_bia'); end if;
      if wk % 4 = 0 then insert into body_measurements (occurred_at, local_date, tz_offset_minutes, measurement_type, value) values ((ts || 'T01:40:00Z')::timestamptz, d, 330, 'waist', round(86.0 - 0.4 * wk, 1)); end if;
    end if;
    if dow in (2, 6) then
      insert into cardio_sessions (occurred_at, local_date, tz_offset_minutes, activity, duration_s, distance_m, avg_speed_mps, incline_pct, intensity) values ((ts || 'T00:30:00Z')::timestamptz, d, 330, 'treadmill', 1500, 2800, 1.87, 1.0, 'moderate');
    end if;
  end loop;

  -- supplement with a pause during the exam break
  insert into supplements (id, name, category) values (sup, 'Creatine monohydrate', 'performance');
  perform pfs_new_version('supplement_phases', jsonb_build_object('id', ph1, 'entity_id', sup, 'effective_from', '2026-08-03T00:00:00Z', 'status', 'active', 'dose_amount', 5, 'dose_unit', 'g', 'times_per_day', 1, 'max_daily_dose', 10), 'start');
  perform pfs_new_version('supplement_phases', jsonb_build_object('id', ph2, 'entity_id', sup, 'effective_from', '2026-09-14T00:00:00Z', 'status', 'paused'), 'exam break');
  perform pfs_new_version('supplement_phases', jsonb_build_object('id', ph3, 'entity_id', sup, 'effective_from', '2026-09-21T00:00:00Z', 'status', 'active', 'dose_amount', 5, 'dose_unit', 'g', 'times_per_day', 1, 'max_daily_dose', 10), 'restart');
  for i in 0..83 loop
    d := d0 + i; ts := d::text;
    continue when d between '2026-09-14' and '2026-09-20';
    ph := case when d < '2026-09-14' then ph1 else ph3 end;
    insert into supplement_logs (supplement_id, phase_id, outcome, quantity, unit, occurred_at, local_date, tz_offset_minutes) values
      (sup, ph, case when abs(hashtext('sp' || ts)) % 10 = 0 then 'missed' else 'taken' end, 5, 'g', (ts || 'T03:00:00Z')::timestamptz, d, 330);
  end loop;

  -- meals, targets and a two-week plan
  insert into meals (id, title, category, protein_g, calories_kcal) values (m1, 'Oatmeal bowl', 'breakfast', 28, 420), (m2, 'Egg and rice plate', 'lunch', 35, 520), (m3, 'Soya curry', 'dinner', 40, 560);
  insert into meal_ingredients (meal_id, name, quantity, unit, protein_g) values (m1, 'oats', 60, 'g', 8), (m1, 'curd', 150, 'g', 6), (m2, 'eggs', 3, 'pcs', 18);
  perform pfs_new_version('personal_targets', jsonb_build_object('entity_id', md5('sample:targets')::uuid, 'effective_from', '2026-08-03T00:00:00Z', 'protein_g', 140, 'water_ml', 2500, 'step_target', 10000), 'initial');
  for i in 70..83 loop
    d := d0 + i;
    insert into meal_plan_entries (local_date, slot, meal_id, status) values (d, 'breakfast', m1, case when d < '2026-10-22' then 'eaten' else 'planned' end),
      (d, 'lunch', m2, case when d < '2026-10-22' then 'eaten' else 'planned' end), (d, 'dinner', m3, case when d < '2026-10-22' then 'eaten' else 'planned' end);
  end loop;

  -- muscle self-assessments (the user's own ratings) and a priority
  a1 := md5('sample:a1')::uuid; a2 := md5('sample:a2')::uuid; a3 := md5('sample:a3')::uuid;
  insert into muscle_assessments (id, occurred_at, local_date, tz_offset_minutes) values (a1, '2026-08-03T12:00:00Z', '2026-08-03', 330), (a2, '2026-08-31T12:00:00Z', '2026-08-31', 330), (a3, '2026-09-28T12:00:00Z', '2026-09-28', 330);
  insert into muscle_assessment_items (assessment_id, muscle_id, level) values
    (a1, md5('muscles:rear_delts')::uuid, 1), (a1, md5('muscles:side_delts')::uuid, 3), (a1, md5('muscles:front_delts')::uuid, 4), (a1, md5('muscles:biceps')::uuid, 3), (a1, md5('muscles:lats')::uuid, 3),
    (a2, md5('muscles:rear_delts')::uuid, 2), (a2, md5('muscles:side_delts')::uuid, 3), (a2, md5('muscles:biceps')::uuid, 3),
    (a3, md5('muscles:rear_delts')::uuid, 2), (a3, md5('muscles:side_delts')::uuid, 3), (a3, md5('muscles:front_delts')::uuid, 4), (a3, md5('muscles:biceps')::uuid, 4);
  perform pfs_new_version('muscle_priorities', jsonb_build_object('entity_id', md5('muscles:rear_delts')::uuid, 'effective_from', '2026-08-03T00:00:00Z', 'priority', 1), 'weak point');

  -- a minor shoulder issue with pain entries and a restriction on one exercise
  insert into injuries (id, name, body_region_id, side, start_date, severity, status, description) values (inj, 'Right shoulder discomfort', md5('body_regions:shoulder')::uuid, 'right', '2026-09-01', 'moderate', 'recovering', 'Felt during pressing.');
  insert into injury_updates (injury_id, note, status, occurred_at, local_date, tz_offset_minutes) values (inj, 'Improving with lighter pressing.', 'recovering', '2026-09-08T12:00:00Z', '2026-09-08', 330);
  insert into pain_entries (body_region_id, side, level, injury_id, effect_on_training, occurred_at, local_date, tz_offset_minutes) values
    (md5('body_regions:shoulder')::uuid, 'right', 4, inj, 'minor', '2026-09-02T12:00:00Z', '2026-09-02', 330),
    (md5('body_regions:shoulder')::uuid, 'right', 3, inj, 'none', '2026-09-09T12:00:00Z', '2026-09-09', 330),
    (md5('body_regions:shoulder')::uuid, 'right', 2, inj, 'none', '2026-09-16T12:00:00Z', '2026-09-16', 330);
  insert into exercise_restrictions (injury_id, exercise_id, kind, source, note, active_from) values (inj, ex_incl, 'modify', 'self', 'Use a lighter load and a neutral grip.', '2026-09-01');

  -- goals and milestones
  insert into goals (id, type, title, target_metric, target_value, target_unit, start_date, target_date, status) values
    (md5('sample:g1')::uuid, 'cutting', 'Slow cut to 15 percent body fat', 'body_fat_pct', 15, 'pct', '2026-08-03', '2026-12-01', 'active'),
    (md5('sample:g2')::uuid, 'strength', 'Bench press estimated 1RM of 100 kg', 'est_1rm:' || ex_bench, 100, 'kg', '2026-08-03', null, 'active');
  insert into milestones (goal_id, title, target_value) values (md5('sample:g1')::uuid, 'Reach 18 percent', 18), (md5('sample:g2')::uuid, 'Reach 90 kg', 90);
end $$;
