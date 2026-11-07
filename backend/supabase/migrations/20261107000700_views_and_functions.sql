-- Stage 2 / read views and helper functions. Views use security_invoker so row level security still applies to the caller.

create function pfs_local_today() returns date language sql stable as $$
  select (now() at time zone coalesce((select time_zone from settings where deleted_at is null limit 1), 'UTC'))::date $$;

-- A day is a break day when an approved (not cancelled) full or modified break covers it.
-- A reduced-schedule break does not excuse days: the schedule entries already reflect the reduced plan.
create function pfs_is_break_day(p_date date) returns boolean language sql stable as $$
  select exists (select 1 from planned_breaks b where b.deleted_at is null and b.status <> 'cancelled'
                   and b.mode in ('full', 'modified') and p_date between b.start_date and b.end_date) $$;

create view v_session_summary with (security_invoker = true) as
select s.id as session_id, s.local_date, s.name, s.status, s.occurred_at as started_at, s.ended_at,
  case when s.ended_at is not null then greatest(0, extract(epoch from (s.ended_at - s.occurred_at))::integer - s.paused_seconds) end as duration_s,
  count(distinct se.id) filter (where se.status in ('done', 'added')) as exercises_done,
  count(distinct se.id) filter (where se.status = 'skipped') as exercises_skipped,
  count(st.id) filter (where st.set_type = 'working' and st.completed) as working_sets,
  coalesce(sum(st.reps) filter (where st.set_type = 'working' and st.completed), 0) as total_reps,
  coalesce(sum(st.weight_kg * st.reps) filter (where st.set_type = 'working' and st.completed), 0)::numeric(12,2) as volume_kg,
  (select coalesce(array_agg(distinct m.key order by m.key), '{}'::text[])
     from session_exercises x
     join exercise_muscles em on em.exercise_id = x.exercise_id and em.role = 'primary' and em.deleted_at is null
     join muscles m on m.id = em.muscle_id
    where x.session_id = s.id and x.status <> 'skipped' and x.deleted_at is null) as muscles_trained
from workout_sessions s
left join session_exercises se on se.session_id = s.id and se.deleted_at is null
left join sets st on st.session_exercise_id = se.id and st.deleted_at is null
where s.deleted_at is null
group by s.id;

-- One row per exercise per session, with the previous session of the same exercise next to it (session comparison).
create view v_exercise_session_stats with (security_invoker = true) as
with per as (
  select se.exercise_id, s.id as session_id, s.local_date, s.occurred_at,
    count(st.id) filter (where st.set_type = 'working' and st.completed) as working_sets,
    coalesce(sum(st.reps) filter (where st.set_type = 'working' and st.completed), 0) as total_reps,
    coalesce(sum(st.weight_kg * st.reps) filter (where st.set_type = 'working' and st.completed), 0)::numeric(12,2) as volume_kg,
    max(st.weight_kg) filter (where st.set_type = 'working' and st.completed) as top_weight_kg
  from session_exercises se
  join workout_sessions s on s.id = se.session_id and s.deleted_at is null and s.status <> 'abandoned'
  left join sets st on st.session_exercise_id = se.id and st.deleted_at is null
  where se.deleted_at is null and se.status <> 'skipped'
  group by se.exercise_id, s.id
)
select per.*,
  lag(per.session_id) over w as prev_session_id, lag(per.volume_kg) over w as prev_volume_kg,
  lag(per.total_reps) over w as prev_total_reps, lag(per.top_weight_kg) over w as prev_top_weight_kg
from per window w as (partition by per.exercise_id order by per.occurred_at);

create view v_weekly_exercise_volume with (security_invoker = true) as
select date_trunc('week', st.local_date)::date as week_start, se.exercise_id,
  count(*) filter (where st.set_type = 'working' and st.completed) as working_sets,
  coalesce(sum(st.reps) filter (where st.set_type = 'working' and st.completed), 0) as total_reps,
  coalesce(sum(st.weight_kg * st.reps) filter (where st.set_type = 'working' and st.completed), 0)::numeric(12,2) as volume_kg
from sets st join session_exercises se on se.id = st.session_exercise_id and se.deleted_at is null
where st.deleted_at is null group by 1, 2;

-- Which template versions (and so which prescriptions) used each exercise, and when.
create view v_exercise_usage with (security_invoker = true) as
select te.exercise_id, tv.entity_id as template_id, tv.id as template_version_id, tv.name as template_name,
  tv.effective_from, tv.effective_to, te.target_sets, te.rep_min, te.rep_max
from template_exercises te join template_versions tv on tv.id = te.template_version_id
where te.deleted_at is null and tv.deleted_at is null;

-- Split activation periods: start, end, duration and the reasons recorded when switching.
create view v_split_periods with (security_invoker = true) as
with ev as (
  select e.split_id, e.status, e.occurred_at, e.local_date, e.reason,
    lead(e.local_date) over w as next_date, lead(e.reason) over w as next_reason
  from split_status_events e where e.deleted_at is null
  window w as (partition by e.split_id order by e.occurred_at, e.rev)
)
select ev.split_id, sv.name, sv.pattern, ev.local_date as start_date, ev.next_date as end_date,
  coalesce(ev.next_date, pfs_local_today()) - ev.local_date as duration_days,
  ev.reason as start_reason, ev.next_reason as end_reason
from ev
left join lateral (select v.name, v.pattern from split_versions v
                    where v.entity_id = ev.split_id and v.deleted_at is null and v.effective_from <= ev.occurred_at
                      and (v.effective_to is null or ev.occurred_at < v.effective_to) limit 1) sv on true
where ev.status = 'active';

-- Attendance. Planned rest days, rescheduled originals and approved break days are never counted as missed.
-- Week buckets start on Monday (the week_start setting only affects display).
create view v_attendance_daily with (security_invoker = true) as
select e.id as schedule_entry_id, e.local_date, e.status, e.is_rest_day, e.session_id,
  pfs_is_break_day(e.local_date) as is_break_day,
  (not e.is_rest_day and e.status <> 'rescheduled' and not pfs_is_break_day(e.local_date)) as is_scheduled_training,
  (e.status in ('completed', 'replaced')) as is_done,
  (not e.is_rest_day and not pfs_is_break_day(e.local_date)
     and (e.status = 'skipped' or (e.status = 'planned' and e.local_date < pfs_local_today()))) as is_missed
from schedule_entries e where e.deleted_at is null;

create view v_consistency_weekly with (security_invoker = true) as
select date_trunc('week', local_date)::date as week_start,
  count(*) filter (where is_scheduled_training and (is_done or is_missed)) as scheduled,
  count(*) filter (where is_scheduled_training and is_done) as completed,
  count(*) filter (where is_missed) as missed,
  count(*) filter (where is_break_day) as break_days,
  round(100.0 * count(*) filter (where is_scheduled_training and is_done)
        / nullif(count(*) filter (where is_scheduled_training and (is_done or is_missed)), 0), 1) as consistency_pct
from v_attendance_daily group by 1;

-- Streak of completed scheduled sessions since the last miss. Rest days and break days neither extend nor break it.
create view v_current_streak with (security_invoker = true) as
with t as (select local_date, is_done, is_missed from v_attendance_daily where is_scheduled_training and (is_done or is_missed)),
g as (select t.*, sum(case when is_missed then 1 else 0 end) over (order by local_date rows unbounded preceding) as miss_group from t),
runs as (select miss_group, count(*) filter (where is_done) as run_length from g group by miss_group)
select coalesce((select run_length from runs order by miss_group desc limit 1), 0) as current_streak,
       coalesce((select max(run_length) from runs), 0) as longest_streak;

-- Compare two versions of a template: exercises added, removed, and changed prescriptions.
create function api_compare_template_versions(p_a uuid, p_b uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare r jsonb;
begin
  perform pfs_require_owner();
  with a as (select exercise_id, position, target_sets, rep_min, rep_max, start_weight_kg, rest_s from template_exercises where template_version_id = p_a and deleted_at is null),
       b as (select exercise_id, position, target_sets, rep_min, rep_max, start_weight_kg, rest_s from template_exercises where template_version_id = p_b and deleted_at is null)
  select jsonb_build_object(
    'added', coalesce((select jsonb_agg(to_jsonb(b)) from b where b.exercise_id not in (select exercise_id from a)), '[]'::jsonb),
    'removed', coalesce((select jsonb_agg(to_jsonb(a)) from a where a.exercise_id not in (select exercise_id from b)), '[]'::jsonb),
    'changed', coalesce((select jsonb_agg(jsonb_build_object('exercise_id', a.exercise_id, 'from', to_jsonb(a), 'to', to_jsonb(b)))
                           from a join b on b.exercise_id = a.exercise_id where to_jsonb(a) is distinct from to_jsonb(b)), '[]'::jsonb))
    into r;
  return jsonb_build_object('data', r, 'meta', pfs_meta());
end $$;

-- Grants: views are readable by the signed-in owner (RLS decides), helper functions are callable.
do $$
declare v text;
begin
  for v in select unnest(array['v_session_summary', 'v_exercise_session_stats', 'v_weekly_exercise_volume', 'v_exercise_usage',
                               'v_split_periods', 'v_attendance_daily', 'v_consistency_weekly', 'v_current_streak']) loop
    execute format('grant select on %I to authenticated', v);
  end loop;
end $$;
grant execute on function pfs_local_today(), pfs_is_break_day(date), api_compare_template_versions(uuid, uuid) to authenticated;
