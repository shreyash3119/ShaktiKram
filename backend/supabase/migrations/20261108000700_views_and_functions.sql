-- Stage 3 / read views and helper functions. Views use security_invoker so row level security still applies to the caller.
-- Calculated values are labelled: value_kind is 'estimated' or 'user_assessment', never 'measured'.

create function pfs_tz() returns text language sql stable as $$
  select coalesce((select time_zone from settings where deleted_at is null limit 1), 'UTC') $$;
create function pfs_local_date(p_ts timestamptz) returns date language sql stable as $$
  select (p_ts at time zone pfs_tz())::date $$;

-- One category per rating level (shared/vocabulary/scales.json).
create function pfs_muscle_category(p_level integer) returns text language sql immutable as $$
  select case p_level when 1 then 'high_priority' when 2 then 'needs_improvement' when 3 then 'average_maintenance'
                      when 4 then 'above_average' when 5 then 'well_developed' end $$;

-- The personal targets that applied on a local date.
create function pfs_target_on(p_date date) returns personal_targets language sql stable as $$
  select t.* from personal_targets t
   where t.deleted_at is null and pfs_local_date(t.effective_from) <= p_date
     and (t.effective_to is null or p_date < pfs_local_date(t.effective_to))
   order by t.version desc limit 1 $$;

-- Body composition. Fat and lean mass need a body-fat reading AND a weight on the same day; weight alone never gives body fat.
-- Readings from different methods stay in separate rows and are not treated as equivalent.
create view v_body_composition with (security_invoker = true) as
select bf.id as measurement_id, bf.local_date, bf.method, bf.source, bf.value as body_fat_pct, w.weight_kg,
  case when w.weight_kg is not null then round(w.weight_kg * bf.value / 100, 2) end as fat_mass_kg,
  case when w.weight_kg is not null then round(w.weight_kg - w.weight_kg * bf.value / 100, 2) end as lean_mass_kg,
  'estimated'::text as value_kind
from body_measurements bf
left join lateral (select m.value as weight_kg from body_measurements m
                    where m.measurement_type = 'weight' and m.deleted_at is null and m.local_date = bf.local_date
                    order by m.occurred_at desc limit 1) w on true
where bf.measurement_type = 'body_fat' and bf.deleted_at is null;

create view v_measurement_latest with (security_invoker = true) as
select distinct on (measurement_type, coalesce(method, ''), coalesce(custom_label, ''), coalesce(side, ''))
  measurement_type, method, custom_label, side, value, local_date, id as measurement_id
from body_measurements where deleted_at is null
order by measurement_type, coalesce(method, ''), coalesce(custom_label, ''), coalesce(side, ''), occurred_at desc;

create view v_sleep_weekly with (security_invoker = true) as
select date_trunc('week', s.local_date)::date as week_start, count(*) as nights,
  round(avg(s.duration_s)) as avg_duration_s, round(avg(s.quality), 1) as avg_quality,
  round(stddev_pop(((extract(epoch from (s.sleep_at at time zone pfs_tz())::time) / 60 + 360)::numeric % 1440)), 0) as bedtime_spread_min
from sleep_logs s where s.deleted_at is null and not s.is_nap group by 1;

create view v_steps_weekly with (security_invoker = true) as
select date_trunc('week', local_date)::date as week_start, count(*) as days_logged, round(avg(steps)) as avg_steps, max(steps) as max_steps,
  count(*) filter (where target_steps is not null and steps >= target_steps) as days_on_target
from daily_steps where deleted_at is null group by 1;

create view v_cardio_weekly with (security_invoker = true) as
select date_trunc('week', local_date)::date as week_start, count(*) as sessions, sum(duration_s) as total_duration_s,
  coalesce(sum(distance_m), 0) as total_distance_m,
  round((sum(duration_s) filter (where distance_m > 0)) / nullif((sum(distance_m) filter (where distance_m > 0)) / 1000.0, 0)) as avg_pace_s_per_km
from cardio_sessions where deleted_at is null group by 1;

-- Nutrition of a saved meal: its own figures, else the sum of its ingredients, else the sum of its component meals (one level; each
-- component counts its own figures or its ingredients). Always an estimate.
create view v_meal_nutrition with (security_invoker = true) as
select m.id as meal_id, m.title, m.category,
  coalesce(m.calories_kcal, i.c, k.c) as calories_kcal, coalesce(m.protein_g, i.p, k.p) as protein_g,
  coalesce(m.carbs_g, i.cb, k.cb) as carbs_g, coalesce(m.fat_g, i.f, k.f) as fat_g, coalesce(m.fibre_g, i.fb, k.fb) as fibre_g,
  case when m.calories_kcal is not null or m.protein_g is not null then 'meal'
       when i.c is not null or i.p is not null then 'ingredients'
       when k.c is not null or k.p is not null then 'components' end as nutrition_source,
  (m.nutrition_is_estimate or (m.calories_kcal is null and m.protein_g is null)) as is_estimate
from meals m
left join lateral (select sum(calories_kcal) c, sum(protein_g) p, sum(carbs_g) cb, sum(fat_g) f, sum(fibre_g) fb
                     from meal_ingredients where meal_id = m.id and deleted_at is null) i on true
left join lateral (select sum(coalesce(cm.calories_kcal, ci.c) * mc.servings) c, sum(coalesce(cm.protein_g, ci.p) * mc.servings) p,
                          sum(coalesce(cm.carbs_g, ci.cb) * mc.servings) cb, sum(coalesce(cm.fat_g, ci.f) * mc.servings) f,
                          sum(coalesce(cm.fibre_g, ci.fb) * mc.servings) fb
                     from meal_components mc join meals cm on cm.id = mc.component_meal_id and cm.deleted_at is null
                     left join lateral (select sum(calories_kcal) c, sum(protein_g) p, sum(carbs_g) cb, sum(fat_g) f, sum(fibre_g) fb
                                          from meal_ingredients where meal_id = cm.id and deleted_at is null) ci on true
                    where mc.meal_id = m.id and mc.deleted_at is null) k on true
where m.deleted_at is null;

-- Planned versus eaten, against the protein target of that day. Optional: days without plan entries simply have no row.
create view v_daily_nutrition with (security_invoker = true) as
select p.local_date,
  coalesce(sum(n0.protein_g * p.servings), 0)::numeric(9,1) as planned_protein_g,
  coalesce(sum(n0.calories_kcal * p.servings), 0)::numeric(9,1) as planned_calories_kcal,
  coalesce(sum(case when p.status = 'eaten' then n0.protein_g * p.servings when p.status = 'replaced' then n1.protein_g * p.servings end), 0)::numeric(9,1) as eaten_protein_g,
  coalesce(sum(case when p.status = 'eaten' then n0.calories_kcal * p.servings when p.status = 'replaced' then n1.calories_kcal * p.servings end), 0)::numeric(9,1) as eaten_calories_kcal,
  (pfs_target_on(p.local_date)).protein_g as protein_target_g,
  round(100 * sum(n0.protein_g * p.servings) / nullif((pfs_target_on(p.local_date)).protein_g, 0), 1) as planned_protein_pct_of_target,
  'estimated'::text as value_kind
from meal_plan_entries p
left join v_meal_nutrition n0 on n0.meal_id = p.meal_id
left join v_meal_nutrition n1 on n1.meal_id = p.replaced_by_meal_id
where p.deleted_at is null group by p.local_date;

create view v_daily_hydration with (security_invoker = true) as
select w.local_date, sum(w.amount_ml) as total_ml, (pfs_target_on(w.local_date)).water_ml as target_ml,
  round(100.0 * sum(w.amount_ml) / nullif((pfs_target_on(w.local_date)).water_ml, 0), 1) as pct_of_target
from water_logs w where w.deleted_at is null group by w.local_date;

-- Supplements. Adherence counts only phases whose status was active. Intentional skips are left out of the logged percentage.
create view v_supplement_adherence with (security_invoker = true) as
with ph as (
  select p.id as phase_id, p.entity_id as supplement_id, p.times_per_day, p.days_of_week, pfs_local_date(p.effective_from) as start_d,
    case when p.effective_to is null then pfs_local_today() else pfs_local_date(p.effective_to) - 1 end as end_d
  from supplement_phases p where p.status = 'active' and p.deleted_at is null),
sched as (
  select ph.phase_id, count(*) filter (where cardinality(ph.days_of_week) = 0 or extract(isodow from g)::int = any (ph.days_of_week)) as scheduled_days
  from ph cross join lateral generate_series(ph.start_d, ph.end_d, interval '1 day') g group by ph.phase_id),
lg as (
  select phase_id, count(*) filter (where outcome = 'taken') as taken, count(*) filter (where outcome = 'missed') as missed,
         count(*) filter (where outcome = 'skipped') as skipped
  from supplement_logs where deleted_at is null and phase_id is not null group by phase_id)
select ph.supplement_id, ph.phase_id, ph.start_d, ph.end_d,
  coalesce(s.scheduled_days, 0) * ph.times_per_day as expected_doses,
  coalesce(lg.taken, 0) as taken, coalesce(lg.missed, 0) as missed, coalesce(lg.skipped, 0) as skipped,
  round(100.0 * coalesce(lg.taken, 0) / nullif(coalesce(lg.taken, 0) + coalesce(lg.missed, 0), 0), 1) as logged_adherence_pct,
  round(100.0 * coalesce(lg.taken, 0) / nullif(coalesce(s.scheduled_days, 0) * ph.times_per_day, 0), 1) as expected_adherence_pct
from ph left join sched s on s.phase_id = ph.phase_id left join lg on lg.phase_id = ph.phase_id;

create view v_supplement_summary with (security_invoker = true) as
select s.id as supplement_id, s.name,
  (select p.status from supplement_phases p where p.entity_id = s.id and p.effective_to is null and p.deleted_at is null) as current_status,
  (select min(pfs_local_date(p.effective_from)) from supplement_phases p where p.entity_id = s.id and p.deleted_at is null) as first_start_date,
  (select count(*) from supplement_phases p where p.entity_id = s.id and p.deleted_at is null) as phase_count,
  (select coalesce(sum(greatest(0, (case when p.effective_to is null then pfs_local_today() else pfs_local_date(p.effective_to) - 1 end) - pfs_local_date(p.effective_from) + 1)), 0)
     from supplement_phases p where p.entity_id = s.id and p.status = 'active' and p.deleted_at is null) as active_days_total
from supplements s where s.deleted_at is null;

-- Flags days where the doses taken added up to more than the limit the user recorded. An observation, not advice.
create view v_supplement_limit_flags with (security_invoker = true) as
select l.supplement_id, l.local_date, sum(l.quantity) as total_taken, max(p.max_daily_dose) as recorded_daily_limit,
  (sum(l.quantity) > max(p.max_daily_dose)) as exceeds_recorded_limit
from supplement_logs l join supplement_phases p on p.id = l.phase_id
where l.outcome = 'taken' and l.deleted_at is null and p.max_daily_dose is not null
group by l.supplement_id, l.local_date;

-- Muscle ratings: the user's latest, previous and first assessment, with the category for the latest level.
-- assessment_change describes a change in the user's assessment, not measured growth.
create view v_muscle_ratings with (security_invoker = true) as
with items as (
  select i.muscle_id, i.level, a.local_date,
    row_number() over (partition by i.muscle_id order by a.occurred_at desc, a.rev desc) as rn_desc,
    row_number() over (partition by i.muscle_id order by a.occurred_at asc, a.rev asc) as rn_asc
  from muscle_assessment_items i join muscle_assessments a on a.id = i.assessment_id
  where i.deleted_at is null and a.deleted_at is null),
prio as (
  select entity_id as muscle_id, priority, effective_to, lag(priority) over (partition by entity_id order by version) as previous_priority
  from muscle_priorities where deleted_at is null)
select m.id as muscle_id, m.key as muscle_key, m.group_key,
  cur.level as current_level, pfs_muscle_category(cur.level) as category, cur.local_date as rated_on,
  prv.level as previous_level, bas.level as baseline_level,
  case when cur.level is null then null when prv.level is null then 'first_assessment' when cur.level > prv.level then 'higher_rating'
       when cur.level < prv.level then 'lower_rating' else 'same_rating' end as assessment_change,
  pr.priority as current_priority, pr.previous_priority,
  case when pr.priority is null then null when pr.previous_priority is null then 'new' when pr.priority < pr.previous_priority then 'raised'
       when pr.priority > pr.previous_priority then 'lowered' else 'unchanged' end as priority_change,
  'user_assessment'::text as value_kind
from muscles m
left join items cur on cur.muscle_id = m.id and cur.rn_desc = 1
left join items prv on prv.muscle_id = m.id and prv.rn_desc = 2
left join items bas on bas.muscle_id = m.id and bas.rn_asc = 1
left join prio pr on pr.muscle_id = m.id and pr.effective_to is null
where m.deleted_at is null;

create view v_reassessment_due with (security_invoker = true) as
select la.last_date as last_assessment_date, s.reassessment_interval_days as interval_days,
  la.last_date + s.reassessment_interval_days as next_due_date,
  (la.last_date is null or pfs_local_today() >= la.last_date + s.reassessment_interval_days) as is_due,
  greatest(0, pfs_local_today() - (la.last_date + s.reassessment_interval_days)) as days_overdue
from (select reassessment_interval_days from settings where deleted_at is null limit 1) s
left join lateral (select max(local_date) as last_date from muscle_assessments where deleted_at is null) la on true;

-- Training exposure per muscle and week. Kept separate from ratings: set counts say nothing about how developed a muscle is.
create view v_muscle_exposure_weekly with (security_invoker = true) as
select date_trunc('week', st.local_date)::date as week_start, em.muscle_id,
  count(*) filter (where em.role = 'primary') as direct_sets,
  count(*) filter (where em.role in ('secondary', 'indirect')) as indirect_sets,
  count(distinct st.local_date) as training_days, round(avg(st.rpe), 1) as avg_rpe, round(avg(st.rir), 1) as avg_rir
from sets st
join session_exercises se on se.id = st.session_exercise_id and se.deleted_at is null and se.status <> 'skipped'
join exercise_muscles em on em.exercise_id = se.exercise_id and em.deleted_at is null
where st.deleted_at is null and st.set_type = 'working' and st.completed
group by 1, 2;

-- Does a muscle the user marked as weak (rating or priority) receive direct work? The rating and the exposure are shown side by side.
create view v_weak_point_attention with (security_invoker = true) as
select r.muscle_id, r.muscle_key, r.current_level, r.category, r.current_priority,
  coalesce(x.direct_sets_28d, 0) as direct_sets_28d, coalesce(x.direct_training_days_28d, 0) as direct_training_days_28d,
  'Training exposure is shown beside your rating. It does not measure muscle development.'::text as note
from v_muscle_ratings r
left join lateral (
  select count(*) as direct_sets_28d, count(distinct st.local_date) as direct_training_days_28d
  from sets st
  join session_exercises se on se.id = st.session_exercise_id and se.deleted_at is null and se.status <> 'skipped'
  join exercise_muscles em on em.exercise_id = se.exercise_id and em.deleted_at is null and em.role = 'primary' and em.muscle_id = r.muscle_id
  where st.deleted_at is null and st.set_type = 'working' and st.completed and st.local_date >= pfs_local_today() - 27) x on true
where r.category in ('high_priority', 'needs_improvement') or r.current_priority = 1;

-- Injuries. suggest_professional_review is an observation flag (severe, high or rising pain), not a diagnosis.
create view v_injury_summary with (security_invoker = true) as
select i.id as injury_id, i.name, i.body_region_id, br.key as body_region_key, i.side, i.status, i.severity, i.start_date, i.resolved_on,
  coalesce(i.resolved_on, pfs_local_today()) - i.start_date as days_since_start,
  (select count(*) from injury_updates u where u.injury_id = i.id and u.deleted_at is null) as update_count,
  lp.level as latest_pain_level, lp.local_date as latest_pain_date, pp.level as previous_pain_level,
  (i.status <> 'resolved' and (i.severity = 'severe' or coalesce(lp.level, 0) >= 7
     or (lp.level is not null and pp.level is not null and lp.level - pp.level >= 2))) as suggest_professional_review
from injuries i join body_regions br on br.id = i.body_region_id
left join lateral (select p.level, p.local_date from pain_entries p where p.injury_id = i.id and p.deleted_at is null order by p.occurred_at desc limit 1) lp on true
left join lateral (select p.level from pain_entries p where p.injury_id = i.id and p.deleted_at is null order by p.occurred_at desc offset 1 limit 1) pp on true
where i.deleted_at is null;

create view v_injury_by_region with (security_invoker = true) as
select br.key as body_region_key, count(*) as total, count(*) filter (where i.status = 'active') as active_count,
  count(*) filter (where i.status = 'recovering') as recovering_count, count(*) filter (where i.status = 'resolved') as resolved_count,
  (select count(*) from pain_entries p where p.body_region_id = br.id and p.deleted_at is null and p.effect_on_training = 'stopped_training') as stopped_training_entries
from injuries i join body_regions br on br.id = i.body_region_id where i.deleted_at is null group by br.id, br.key;

-- Planned exercises that conflict with a recorded restriction (an active restriction, not tied to a resolved injury).
create function api_restriction_warnings(p_exercise_ids uuid[], p_on date default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare d date := coalesce(p_on, pfs_local_today()); r jsonb;
begin
  perform pfs_require_owner();
  select coalesce(jsonb_agg(jsonb_build_object('exercise_id', e.id, 'exercise_name', e.name, 'restriction_id', x.id, 'kind', x.kind,
      'source', x.source, 'note', x.note, 'injury_id', x.injury_id, 'injury_status', i.status,
      'suggestion', 'review_or_modify_before_training') order by e.name, x.id), '[]'::jsonb)
    into r
  from exercises e join exercise_restrictions x on x.exercise_id = e.id
  left join injuries i on i.id = x.injury_id and i.deleted_at is null
  where e.id = any (p_exercise_ids) and x.deleted_at is null and x.active_from <= d and (x.active_to is null or d <= x.active_to)
    and (x.injury_id is null or i.status in ('active', 'recovering'));
  return jsonb_build_object('data', jsonb_build_object('warnings', r), 'meta', pfs_meta());
end $$;

-- What reminders fire in a window (at most 8 days). Workout reminders pause on break days; supplement reminders only while the
-- linked supplement is in an active phase; reassessment reminders only when a reassessment is due. Delivery stays on the device.
create function api_due_reminders(p_from timestamptz, p_to timestamptz) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare tz text := pfs_tz(); r jsonb;
begin
  perform pfs_require_owner();
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '8 days' then
    raise exception 'validation_failed: the window must be positive and at most 8 days';
  end if;
  with days as (select g::date as d from generate_series((p_from at time zone tz)::date - 1, (p_to at time zone tz)::date + 1, interval '1 day') g),
  cand as (
    select rr.id, rr.kind, rr.label, rr.linked_table, rr.linked_record_id, rr.paused_until, x.d,
      ((x.d + (rr.schedule ->> 'time')::time) at time zone tz) as fire_at
    from reminder_rules rr cross join days x
    where rr.deleted_at is null and rr.is_enabled and rr.schedule <> '{}'::jsonb
      and (rr.schedule ->> 'type' = 'daily'
        or (rr.schedule ->> 'type' = 'weekly' and (rr.schedule -> 'days') @> to_jsonb(extract(isodow from x.d)::int))
        or (rr.schedule ->> 'type' = 'once' and (rr.schedule ->> 'date')::date = x.d)))
  select coalesce(jsonb_agg(jsonb_build_object('rule_id', c.id, 'kind', c.kind, 'label', c.label, 'fire_at', c.fire_at,
           'linked_table', c.linked_table, 'linked_record_id', c.linked_record_id) order by c.fire_at, c.id), '[]'::jsonb)
    into r
  from cand c
  where c.fire_at >= p_from and c.fire_at < p_to
    and (c.paused_until is null or c.d > c.paused_until)
    and not (c.kind in ('workout', 'leave_for_gym', 'rest_day') and pfs_is_break_day(c.d))
    and not (c.kind = 'supplement' and c.linked_table = 'supplements' and not exists (
          select 1 from supplement_phases p where p.entity_id = c.linked_record_id and p.effective_to is null and p.deleted_at is null and p.status = 'active'))
    and not (c.kind = 'reassessment' and not coalesce((select is_due from v_reassessment_due), true));
  return jsonb_build_object('data', jsonb_build_object('reminders', r), 'meta', pfs_meta());
end $$;

-- Grants: views are readable by the signed-in owner (RLS decides), helper functions are callable.
do $$
declare v text;
begin
  for v in select unnest(array['v_body_composition', 'v_measurement_latest', 'v_sleep_weekly', 'v_steps_weekly', 'v_cardio_weekly',
      'v_meal_nutrition', 'v_daily_nutrition', 'v_daily_hydration', 'v_supplement_adherence', 'v_supplement_summary', 'v_supplement_limit_flags',
      'v_muscle_ratings', 'v_reassessment_due', 'v_muscle_exposure_weekly', 'v_weak_point_attention', 'v_injury_summary', 'v_injury_by_region']) loop
    execute format('grant select on %I to authenticated', v);
  end loop;
end $$;
grant execute on function pfs_tz(), pfs_local_date(timestamptz), pfs_muscle_category(integer), pfs_target_on(date),
  api_restriction_warnings(uuid[], date), api_due_reminders(timestamptz, timestamptz) to authenticated;
