-- Stage 4 / read views. security_invoker, so row level security applies to the caller. Observations only.

create view v_exercise_session_best with (security_invoker = true) as
select w.exercise_id, w.session_id, w.session_local_date as local_date, w.session_occurred_at as occurred_at, w.session_status,
  max(pfs_e1rm(w.weight_kg, w.reps)) as best_e1rm_kg, max(w.weight_kg) as top_weight_kg, max(w.reps) as max_reps, sum(w.weight_kg * w.reps)::numeric(12,2) as volume_kg
from v_working_sets w group by w.exercise_id, w.session_id, w.session_local_date, w.session_occurred_at, w.session_status;

-- Trend per exercise from its last 4 completed sessions within 56 days (rule: shared/calculation_specs/strength.md).
create view v_exercise_trends with (security_invoker = true) as
with ranked as (
  select b.*, row_number() over (partition by b.exercise_id order by b.occurred_at desc) as rn
  from v_exercise_session_best b where b.session_status = 'completed' and b.local_date >= pfs_local_today() - 56),
agg as (
  select exercise_id, count(*) as sessions_considered, max(local_date) as last_session_date,
    calc_trend(jsonb_build_object('series', coalesce(jsonb_agg(best_e1rm_kg order by occurred_at) filter (where best_e1rm_kg is not null), '[]'::jsonb))) as t
  from ranked where rn <= 4 group by exercise_id)
select exercise_id, sessions_considered, last_session_date, t ->> 'signal' as signal, (t ->> 'change_pct')::numeric as change_pct, 'observation'::text as value_kind
from agg;

-- When each muscle was last trained directly (primary role), how often, and the usual gap between sessions.
create view v_muscle_recovery_context with (security_invoker = true) as
with d as (
  select distinct em.muscle_id, w.session_local_date as d
  from v_working_sets w join exercise_muscles em on em.exercise_id = w.exercise_id and em.role = 'primary' and em.deleted_at is null
  where w.session_status = 'completed')
select m.id as muscle_id, m.key as muscle_key, max(d.d) as last_trained_on, pfs_local_today() - max(d.d) as days_since,
  count(d.d) filter (where d.d >= pfs_local_today() - 27) as training_days_28d,
  case when count(d.d) filter (where d.d >= pfs_local_today() - 55) >= 2
       then round((max(d.d) - min(d.d) filter (where d.d >= pfs_local_today() - 55))::numeric / (count(d.d) filter (where d.d >= pfs_local_today() - 55) - 1), 1) end as avg_interval_days
from muscles m left join d on d.muscle_id = m.id where m.deleted_at is null group by m.id, m.key;

-- Equipment right now: occupied lasts 2 hours after the event; unavailable lasts until an "available" event or until the gym setting changes.
create view v_equipment_status with (security_invoker = true) as
select e.id as equipment_id, e.key, e.label,
  case when not e.is_available_at_gym then 'unavailable' when le.status = 'unavailable' then 'unavailable'
       when le.status = 'occupied' and le.occurred_at > now() - interval '2 hours' then 'occupied' else 'available' end as current_status
from equipment e
left join lateral (select x.status, x.occurred_at from equipment_status_events x where x.equipment_id = e.id and x.deleted_at is null order by x.occurred_at desc limit 1) le on true
where e.deleted_at is null;

-- Before, during and after a deload: sessions, average volume per session and average fatigue score (14 days either side).
create view v_deload_comparison with (security_invoker = true) as
select d.id as deload_id, d.start_date, d.end_date, d.status,
  b.sessions as sessions_before, b.avg_volume_kg as avg_volume_before_kg, fb.avg_fatigue as avg_fatigue_before,
  du.sessions as sessions_during, du.avg_volume_kg as avg_volume_during_kg, fd.avg_fatigue as avg_fatigue_during,
  a.sessions as sessions_after, a.avg_volume_kg as avg_volume_after_kg, fa.avg_fatigue as avg_fatigue_after
from deload_periods d
left join lateral (select count(*) as sessions, round(avg(volume_kg)) as avg_volume_kg from v_session_summary where status = 'completed' and local_date >= d.start_date - 14 and local_date < d.start_date) b on true
left join lateral (select count(*) as sessions, round(avg(volume_kg)) as avg_volume_kg from v_session_summary where status = 'completed' and local_date between d.start_date and d.end_date) du on true
left join lateral (select count(*) as sessions, round(avg(volume_kg)) as avg_volume_kg from v_session_summary where status = 'completed' and local_date > d.end_date and local_date <= d.end_date + 14) a on true
left join lateral (select round(avg(fatigue), 1) as avg_fatigue from daily_checkins where deleted_at is null and local_date >= d.start_date - 14 and local_date < d.start_date) fb on true
left join lateral (select round(avg(fatigue), 1) as avg_fatigue from daily_checkins where deleted_at is null and local_date between d.start_date and d.end_date) fd on true
left join lateral (select round(avg(fatigue), 1) as avg_fatigue from daily_checkins where deleted_at is null and local_date > d.end_date and local_date <= d.end_date + 14) fa on true
where d.deleted_at is null;

-- Start, current and source values for a goal (rule: shared/calculation_specs/goals_alternatives.md). Runs as the caller, so RLS applies.
create function pfs_goal_values(p_goal_id uuid) returns jsonb language plpgsql stable as $$
declare g goals%rowtype; t text; ex uuid; meth text; sv numeric; cv numeric; as_of date; src text;
begin
  select * into g from goals where id = p_goal_id;
  if not found then return null; end if;
  t := case g.target_metric when 'body_weight_kg' then 'weight' when 'body_fat_pct' then 'body_fat' when 'waist_cm' then 'waist'
                            when 'chest_cm' then 'chest' when 'arm_cm' then 'arm' when 'thigh_cm' then 'thigh' end;
  if t is not null then
    src := 'body_measurements';
    if t = 'body_fat' then select method into meth from body_measurements where measurement_type = 'body_fat' and deleted_at is null order by occurred_at desc limit 1; end if;
    select value, local_date into cv, as_of from body_measurements where measurement_type = t and deleted_at is null and (t <> 'body_fat' or method = meth) order by occurred_at desc limit 1;
    select value into sv from body_measurements where measurement_type = t and deleted_at is null and (t <> 'body_fat' or method = meth) and local_date >= g.start_date order by occurred_at limit 1;
    if sv is null then
      select value into sv from body_measurements where measurement_type = t and deleted_at is null and (t <> 'body_fat' or method = meth) and local_date < g.start_date order by occurred_at desc limit 1;
    end if;
  elsif g.target_metric like 'est_1rm:%' or g.target_metric like 'max_reps:%' then
    src := 'sets';
    begin ex := split_part(g.target_metric, ':', 2)::uuid; exception when others then ex := null; end;
    if ex is not null then
      if g.target_metric like 'est_1rm:%' then
        select max(best_e1rm_kg), (array_agg(local_date order by best_e1rm_kg desc))[1] into cv, as_of from v_exercise_session_best where exercise_id = ex and session_status = 'completed' and local_date >= g.start_date;
        select max(best_e1rm_kg) into sv from v_exercise_session_best where exercise_id = ex and session_status = 'completed' and local_date < g.start_date;
        if sv is null then select best_e1rm_kg into sv from v_exercise_session_best where exercise_id = ex and session_status = 'completed' and local_date >= g.start_date order by occurred_at limit 1; end if;
      else
        select max(max_reps), (array_agg(local_date order by max_reps desc))[1] into cv, as_of from v_exercise_session_best where exercise_id = ex and session_status = 'completed' and local_date >= g.start_date;
        select max(max_reps) into sv from v_exercise_session_best where exercise_id = ex and session_status = 'completed' and local_date < g.start_date;
        if sv is null then select max_reps into sv from v_exercise_session_best where exercise_id = ex and session_status = 'completed' and local_date >= g.start_date order by occurred_at limit 1; end if;
      end if;
    end if;
  elsif g.target_metric = 'consistency_pct' then
    src := 'v_consistency_weekly'; sv := 0; as_of := pfs_local_today();
    select round(avg(consistency_pct), 1) into cv from v_consistency_weekly where week_start >= pfs_local_today() - 28 and consistency_pct is not null;
  else
    src := 'goal_progress';
    select value, local_date into cv, as_of from goal_progress where goal_id = g.id and deleted_at is null order by local_date desc, created_at desc limit 1;
    select value into sv from goal_progress where goal_id = g.id and deleted_at is null order by local_date, created_at limit 1;
  end if;
  return jsonb_build_object('start_value', sv, 'current_value', cv, 'as_of', as_of, 'source', src);
end $$;

create view v_goal_progress with (security_invoker = true) as
select g.id as goal_id, g.title, g.type, g.status as goal_status, g.target_metric, g.target_value, g.start_date, g.target_date,
  v.vals ->> 'source' as source, (v.vals ->> 'start_value')::numeric as start_value, (v.vals ->> 'current_value')::numeric as current_value, (v.vals ->> 'as_of')::date as as_of,
  c.calc ->> 'status' as progress_status, (c.calc ->> 'progress_pct')::numeric as progress_pct, (c.calc ->> 'reached')::boolean as reached,
  (c.calc ->> 'expected_pct')::numeric as expected_pct, 'observation'::text as value_kind
from goals g
cross join lateral (select pfs_goal_values(g.id) as vals) v
cross join lateral (select calc_goal_progress(jsonb_build_object('start_value', v.vals ->> 'start_value', 'current_value', v.vals ->> 'current_value',
      'target_value', g.target_value, 'start_date', g.start_date, 'target_date', g.target_date, 'today', pfs_local_today())) as calc) c
where g.deleted_at is null and g.status in ('active', 'paused', 'completed');

create view v_goal_milestones with (security_invoker = true) as
select m.id as milestone_id, m.goal_id, m.title, m.target_value, p.start_value, p.current_value,
  (p.start_value is not null and p.current_value is not null and p.start_value <> m.target_value
     and case when m.target_value > p.start_value then p.current_value >= m.target_value else p.current_value <= m.target_value end) as is_reached
from milestones m join v_goal_progress p on p.goal_id = m.goal_id where m.deleted_at is null;

do $$
declare v text;
begin
  for v in select unnest(array['v_working_sets', 'v_exercise_session_best', 'v_exercise_trends', 'v_muscle_recovery_context', 'v_equipment_status',
                               'v_deload_comparison', 'v_goal_progress', 'v_goal_milestones']) loop
    execute format('grant select on %I to authenticated', v);
  end loop;
end $$;
-- Views run as the caller, so the functions they use must be callable by the signed-in owner.
grant execute on function pfs_e1rm(numeric, integer), calc_trend(jsonb), calc_goal_progress(jsonb), pfs_goal_values(uuid) to authenticated;
