-- Stage 3: supplements, meals, targets, hydration.
begin;
do $$
declare
  sid uuid := md5('t:creatine')::uuid; sid2 uuid := md5('t:other')::uuid; ph1 uuid := md5('t:ph1')::uuid; ph2 uuid := md5('t:ph2')::uuid; ph3 uuid := md5('t:ph3')::uuid;
  pl uuid := md5('t:pl')::uuid; ma uuid := md5('t:ma')::uuid; mb uuid := md5('t:mb')::uuid; mc uuid := md5('t:mc')::uuid; tg uuid := md5('t:targets')::uuid;
  r record; n integer;
begin
  -- supplements: phases keep start, pause and restart
  insert into supplements (id, name, category) values (sid, 'Creatine (t)', 'performance'), (sid2, 'Other (t)', 'general');
  perform t_expect_error($q$insert into supplements (name) values ('creatine (T)')$q$, 'uq_supplements_name_alive');
  perform pfs_new_version('supplement_phases', jsonb_build_object('id', ph1, 'entity_id', sid, 'effective_from', '2026-10-01T00:00:00Z', 'status', 'active', 'dose_amount', 5, 'dose_unit', 'g', 'times_per_day', 1, 'max_daily_dose', 10), 'start');
  perform pfs_new_version('supplement_phases', jsonb_build_object('id', ph2, 'entity_id', sid, 'effective_from', '2026-10-11T00:00:00Z', 'status', 'paused'), 'exam stress');
  perform pfs_new_version('supplement_phases', jsonb_build_object('id', ph3, 'entity_id', sid, 'effective_from', '2026-10-21T00:00:00Z', 'status', 'active', 'dose_amount', 5, 'dose_unit', 'g'), 'restart');
  perform t_expect_error(format($q$select pfs_new_version('supplement_phases', %L::jsonb, 'x')$q$, jsonb_build_object('entity_id', sid2, 'effective_from', '2026-10-01T00:00:00Z', 'days_of_week', array[8])), 'ck_supplement_phases_days');
  insert into supplement_logs (supplement_id, phase_id, outcome, quantity, unit, occurred_at, local_date, tz_offset_minutes)
    select sid, ph1, 'taken', 5, 'g', (d::date || 'T12:00:00Z')::timestamptz, d::date, 330 from generate_series('2026-10-01'::date, '2026-10-08'::date, interval '1 day') g(d);
  insert into supplement_logs (supplement_id, phase_id, outcome, occurred_at, local_date, tz_offset_minutes) values
    (sid, ph1, 'missed', '2026-10-09T12:00:00Z', '2026-10-09', 330), (sid, ph1, 'skipped', '2026-10-10T12:00:00Z', '2026-10-10', 330);
  select * into r from v_supplement_adherence where phase_id = ph1;
  assert r.start_d = '2026-10-01' and r.end_d = '2026-10-10' and r.expected_doses = 10 and r.taken = 8 and r.missed = 1 and r.skipped = 1
     and r.expected_adherence_pct = 80.0 and r.logged_adherence_pct = 88.9, format('adherence: %s', to_jsonb(r));
  assert not exists (select 1 from v_supplement_adherence where phase_id = ph2), 'a paused phase is not counted';
  select * into r from v_supplement_summary where supplement_id = sid;
  assert r.current_status = 'active' and r.first_start_date = '2026-10-01' and r.phase_count = 3 and r.active_days_total >= 10, format('summary: %s', to_jsonb(r));
  -- recorded daily limit
  perform pfs_new_version('supplement_phases', jsonb_build_object('id', md5('t:ph4')::uuid, 'entity_id', sid2, 'effective_from', '2026-10-01T00:00:00Z', 'status', 'active', 'max_daily_dose', 10), 'start');
  insert into supplement_logs (supplement_id, phase_id, outcome, quantity, occurred_at, local_date, tz_offset_minutes) values
    (sid2, md5('t:ph4')::uuid, 'taken', 6, '2026-10-05T04:00:00Z', '2026-10-05', 330), (sid2, md5('t:ph4')::uuid, 'taken', 6, '2026-10-05T12:00:00Z', '2026-10-05', 330),
    (sid2, md5('t:ph4')::uuid, 'taken', 6, '2026-10-06T12:00:00Z', '2026-10-06', 330);
  assert (select exceeds_recorded_limit from v_supplement_limit_flags where supplement_id = sid2 and local_date = '2026-10-05'), 'day over the recorded limit is flagged';
  assert not (select exceeds_recorded_limit from v_supplement_limit_flags where supplement_id = sid2 and local_date = '2026-10-06');

  -- meals: own figures, ingredient estimate, and a combination of saved meals
  insert into meals (id, title, category, protein_g, calories_kcal) values (ma, 'Oatmeal (t)', 'breakfast', 30, 400);
  insert into meals (id, title, category) values (mb, 'Egg meal (t)', 'lunch'), (mc, 'Combo (t)', 'dinner');
  insert into meal_ingredients (meal_id, name, quantity, unit, protein_g, calories_kcal) values (mb, 'eggs', 2, 'pcs', 12, 140), (mb, 'milk', 200, 'ml', 13, 120);
  insert into meal_components (meal_id, component_meal_id, servings) values (mc, ma, 1), (mc, mb, 2);
  select * into r from v_meal_nutrition where meal_id = mb;
  assert r.protein_g = 25 and r.calories_kcal = 260 and r.nutrition_source = 'ingredients' and r.is_estimate, format('ingredient estimate: %s', to_jsonb(r));
  select * into r from v_meal_nutrition where meal_id = mc;
  assert r.protein_g = 80 and r.calories_kcal = 920 and r.nutrition_source = 'components', format('combination: %s', to_jsonb(r));
  assert (select nutrition_source from v_meal_nutrition where meal_id = ma) = 'meal';
  perform t_expect_error(format($q$insert into meal_components (meal_id, component_meal_id) values (%L, %L)$q$, ma, ma), 'ck_meal_components_different');
  perform t_expect_error(format($q$insert into meal_plan_entries (local_date, slot, meal_id, status) values ('2026-10-05', 'lunch', %L, 'replaced')$q$, mb), 'ck_meal_plan_entries_replaced_has_meal');

  -- targets are versioned; the plan is compared with the target of its own day
  perform pfs_new_version('personal_targets', jsonb_build_object('entity_id', tg, 'effective_from', '2026-09-01T00:00:00Z', 'protein_g', 100, 'water_ml', 2500, 'step_target', 10000), 'initial');
  perform pfs_new_version('personal_targets', jsonb_build_object('entity_id', tg, 'effective_from', '2026-10-10T00:00:00Z', 'protein_g', 120, 'water_ml', 2500, 'step_target', 10000), 'bulk');
  perform t_expect_error($q$select pfs_new_version('personal_targets', '{"entity_id":"aaaaaaaa-0000-0000-0000-0000000000cc","effective_from":"2026-12-01T00:00:00Z"}'::jsonb, 'x')$q$, 'uq_personal_targets_one_current');
  insert into meal_plan_entries (local_date, slot, meal_id, status, replaced_by_meal_id) values
    ('2026-10-05', 'breakfast', ma, 'eaten', null), ('2026-10-05', 'lunch', mb, 'replaced', ma), ('2026-10-05', 'dinner', mc, 'planned', null),
    ('2026-10-11', 'breakfast', ma, 'planned', null);
  select * into r from v_daily_nutrition where local_date = '2026-10-05';
  assert r.planned_protein_g = 135.0 and r.planned_calories_kcal = 1580.0 and r.eaten_protein_g = 60.0 and r.eaten_calories_kcal = 800.0
     and r.protein_target_g = 100 and r.planned_protein_pct_of_target = 135.0 and r.value_kind = 'estimated', format('day nutrition: %s', to_jsonb(r));
  assert (select protein_target_g from v_daily_nutrition where local_date = '2026-10-11') = 120 and (select planned_protein_pct_of_target from v_daily_nutrition where local_date = '2026-10-11') = 25.0, 'later day uses the later target';
  assert (select protein_target_g from v_daily_nutrition where local_date = '2026-10-05') = 100, 'the old day keeps its old target';

  -- hydration
  insert into water_logs (amount_ml, occurred_at, local_date, tz_offset_minutes) values (500, '2026-10-05T04:00:00Z', '2026-10-05', 330), (750, '2026-10-05T09:00:00Z', '2026-10-05', 330);
  select * into r from v_daily_hydration where local_date = '2026-10-05';
  assert r.total_ml = 1250 and r.target_ml = 2500 and r.pct_of_target = 50.0, format('hydration: %s', to_jsonb(r));
  perform t_expect_error($q$insert into water_logs (amount_ml, occurred_at, local_date, tz_offset_minutes) values (0, now(), current_date, 0)$q$, 'ck_water_logs_amount_positive');
end $$;
rollback;
