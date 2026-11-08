-- Stage 4 / suggestions and summaries. The pfs_* functions are internal; the api_* functions check the owner and wrap the answer.
-- Everything returned is a suggestion or an observation with its reasoning. Nothing is applied automatically.

-- 'avoid' if an avoid restriction applies, 'caution' for uncomfortable or modify, else null. Restrictions tied to a resolved injury do not count.
create function pfs_restriction_kind(p_exercise uuid, p_on date) returns text language sql stable as $$
  select case when bool_or(x.kind = 'avoid') then 'avoid' when count(*) > 0 then 'caution' end
  from exercise_restrictions x left join injuries i on i.id = x.injury_id and i.deleted_at is null
  where x.exercise_id = p_exercise and x.deleted_at is null and x.active_from <= p_on and (x.active_to is null or p_on <= x.active_to)
    and (x.injury_id is null or i.status in ('active', 'recovering')) $$;

create function pfs_next_targets(p_ids uuid[], p_on date) returns jsonb language plpgsql stable as $$
declare ex record; last_session uuid; v_sets jsonb; ts int; rmin int; rmax int; src text; deload boolean; res jsonb; v_out jsonb := '[]'::jsonb;
begin
  deload := exists (select 1 from deload_periods where deleted_at is null and status <> 'cancelled' and p_on between start_date and end_date);
  for ex in select e.id, e.name, e.weight_increment_kg from exercises e where e.id = any (coalesce(p_ids, '{}')) and e.deleted_at is null order by e.name loop
    select w.session_id into last_session from v_working_sets w where w.exercise_id = ex.id and w.session_status = 'completed' order by w.session_occurred_at desc limit 1;
    select coalesce(jsonb_agg(jsonb_build_object('weight_kg', w.weight_kg, 'reps', w.reps, 'rir', w.rir, 'rpe', w.rpe) order by w.set_occurred_at), '[]'::jsonb)
      into v_sets from v_working_sets w where w.session_id = last_session and w.exercise_id = ex.id;
    select te.target_sets, te.rep_min, te.rep_max into ts, rmin, rmax from template_exercises te
      join template_versions tv on tv.id = te.template_version_id and tv.effective_to is null and tv.deleted_at is null
     where te.exercise_id = ex.id and te.deleted_at is null order by tv.effective_from desc limit 1;
    if found then src := 'current_template';
    else
      select (se.prescription_snapshot ->> 'target_sets')::int, (se.prescription_snapshot ->> 'rep_min')::int, (se.prescription_snapshot ->> 'rep_max')::int
        into ts, rmin, rmax from session_exercises se join workout_sessions s on s.id = se.session_id
       where se.exercise_id = ex.id and se.prescription_snapshot is not null and se.deleted_at is null order by s.occurred_at desc limit 1;
      src := case when found then 'last_session' else 'default' end;
    end if;
    res := calc_progression(jsonb_build_object('sets', v_sets, 'rep_min', rmin, 'rep_max', rmax, 'target_sets', ts, 'increment_kg', ex.weight_increment_kg,
             'deload_active', deload, 'restricted', pfs_restriction_kind(ex.id, p_on) = 'avoid' or pfs_restriction_kind(ex.id, p_on) = 'caution'));
    v_out := v_out || jsonb_build_array(res || jsonb_build_object('exercise_id', ex.id, 'exercise_name', ex.name, 'prescription_source', src, 'based_on_session_id', last_session));
  end loop;
  return v_out;
end $$;

create function pfs_readiness(p_on date) returns jsonb language plpgsql stable as $$
declare ci daily_checkins%rowtype; sleep_h numeric; pain numeric; review boolean; inputs jsonb; res jsonb; en record; last_d date; n7 int; tmpl text;
begin
  select * into ci from daily_checkins where local_date = p_on and deleted_at is null;
  select round(sum(duration_s) / 3600.0, 1) into sleep_h from sleep_logs where local_date = p_on and not is_nap and deleted_at is null;
  select max(p.level) into pain from pain_entries p left join injuries i on i.id = p.injury_id and i.deleted_at is null
   where p.deleted_at is null and p.local_date between p_on - 2 and p_on and (p.injury_id is null or i.status in ('active', 'recovering'));
  select coalesce(bool_or(suggest_professional_review), false) into review from v_injury_summary;
  inputs := jsonb_build_object('has_checkin', ci.id is not null, 'energy', ci.energy, 'sleep_quality', ci.sleep_quality, 'soreness', ci.soreness, 'fatigue', ci.fatigue,
    'motivation', ci.motivation, 'stress', ci.stress, 'pain_flag', coalesce(ci.pain_flag, false), 'max_pain_level', pain, 'sleep_hours', sleep_h, 'suggest_professional_review', review);
  res := calc_readiness(inputs);
  select * into en from schedule_entries where local_date = p_on and deleted_at is null;
  select max(local_date), count(*) filter (where local_date >= p_on - 6) into last_d, n7 from workout_sessions where deleted_at is null and status = 'completed' and local_date <= p_on;
  select name into tmpl from template_versions where id = en.template_version_id;
  return res || jsonb_build_object('date', p_on, 'inputs', inputs, 'context', jsonb_build_object(
    'planned_status', en.status, 'planned_is_rest_day', en.is_rest_day, 'planned_template', tmpl, 'is_break_day', pfs_is_break_day(p_on),
    'last_session_date', last_d, 'days_since_last_session', p_on - last_d, 'sessions_last_7_days', n7));
end $$;

create function pfs_deload_signals(p_on date) returns jsonb language plpgsql stable as $$
declare last_dl date; first_s date; wk numeric; fe int; fh int; se int; sh int; dec_n int; sn int; sa numeric; inputs jsonb;
begin
  select max(end_date) into last_dl from deload_periods where deleted_at is null and status <> 'cancelled' and end_date <= p_on;
  select min(local_date) into first_s from workout_sessions where deleted_at is null and status = 'completed';
  wk := case when coalesce(last_dl, first_s) is null then null else round((p_on - coalesce(last_dl, first_s)) / 7.0, 1) end;
  select count(fatigue), count(*) filter (where fatigue >= 4), count(soreness), count(*) filter (where soreness >= 4) into fe, fh, se, sh
    from (select fatigue, soreness from daily_checkins where deleted_at is null and local_date <= p_on order by local_date desc limit 10) q;
  select count(*) into dec_n from v_exercise_trends where signal = 'declining' and last_session_date >= p_on - 21;
  select count(*), round(avg(duration_s) / 3600.0, 1) into sn, sa from sleep_logs where deleted_at is null and not is_nap and local_date between p_on - 6 and p_on;
  inputs := jsonb_build_object('weeks_since_deload', wk, 'fatigue_entries', fe, 'fatigue_high_count', fh, 'soreness_entries', se, 'soreness_high_count', sh,
    'declining_exercises', dec_n, 'sleep_nights', sn, 'avg_sleep_h', sa);
  return calc_deload_signal(inputs) || jsonb_build_object('inputs', inputs);
end $$;

create function pfs_alternatives(p_ex uuid, p_limit integer, p_on date) returns jsonb language sql stable as $$
  with t as (select muscle_id, role from exercise_muscles where exercise_id = p_ex and deleted_at is null),
  tp as (select count(*) as n from t where role = 'primary'), ts as (select count(*) as n from t where role in ('secondary', 'indirect')),
  tcat as (select category from exercises where id = p_ex),
  cand as (
    select e.id, e.name, e.category, e.equipment_id,
      (select count(*) from exercise_muscles em where em.exercise_id = e.id and em.deleted_at is null and em.role = 'primary' and em.muscle_id in (select muscle_id from t where role = 'primary')) as p_over,
      (select count(*) from exercise_muscles em where em.exercise_id = e.id and em.deleted_at is null and em.muscle_id in (select muscle_id from t where role in ('secondary', 'indirect'))) as s_over,
      exists (select 1 from exercise_alternatives a where a.deleted_at is null and ((a.exercise_id = p_ex and a.alternative_id = e.id) or (a.alternative_id = p_ex and a.exercise_id = e.id))) as linked,
      pfs_restriction_kind(e.id, p_on) as restriction, coalesce(es.current_status, 'available') as equipment_status
    from exercises e left join v_equipment_status es on es.equipment_id = e.equipment_id
    where e.deleted_at is null and e.id <> p_ex),
  scored as (
    select c.*, round(coalesce(50.0 * c.p_over / nullif((select n from tp), 0), 0) + coalesce(10.0 * c.s_over / nullif((select n from ts), 0), 0)
      + case when c.category is not null and c.category = (select category from tcat) then 15 else 0 end + case when c.linked then 20 else 0 end
      - case when c.restriction = 'caution' then 30 else 0 end, 1) as score
    from cand c where (c.p_over >= 1 or c.linked) and c.restriction is distinct from 'avoid' and c.equipment_status = 'available'),
  top as (select * from scored order by score desc, name limit p_limit)
  select coalesce(jsonb_agg(jsonb_build_object('exercise_id', id, 'exercise_name', name, 'score', score,
    'reason_codes', to_jsonb(array_remove(array[case when p_over >= 1 then 'same_primary_muscles' end, case when linked then 'linked_alternative' end,
        case when category is not null and category = (select category from tcat) then 'same_category' end, case when restriction = 'caution' then 'restriction_note' end], null)),
    'value_kind', 'suggestion') order by score desc, name), '[]'::jsonb) from top $$;

create function pfs_weak_point_suggestions(p_on date) returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(q.item order by q.muscle_key), '[]'::jsonb) from (
    select a.muscle_key, jsonb_build_object('muscle_key', a.muscle_key, 'category', a.category, 'priority', a.current_priority, 'direct_sets_28d', a.direct_sets_28d,
      'suggestions', coalesce((select jsonb_agg(jsonb_build_object('exercise_id', x.id, 'exercise_name', x.name, 'in_current_split', x.in_split) order by x.in_split, x.name)
        from (select e.id, e.name, exists (
                select 1 from template_exercises te join template_versions tv on tv.id = te.template_version_id and tv.effective_to is null and tv.deleted_at is null
                join split_days sd on sd.template_id = tv.entity_id and sd.deleted_at is null
                join split_versions sv on sv.id = sd.split_version_id and sv.effective_to is null and sv.deleted_at is null
                join splits sp on sp.id = sv.entity_id and sp.status = 'active' and sp.deleted_at is null
               where te.exercise_id = e.id and te.deleted_at is null) as in_split
              from exercises e join exercise_muscles em on em.exercise_id = e.id and em.muscle_id = a.muscle_id and em.role = 'primary' and em.deleted_at is null
              left join v_equipment_status es on es.equipment_id = e.equipment_id
              where e.deleted_at is null and pfs_restriction_kind(e.id, p_on) is distinct from 'avoid' and coalesce(es.current_status, 'available') = 'available'
              order by 3, e.name limit 3) x), '[]'::jsonb),
      'value_kind', 'suggestion', 'note', 'Consider these within your current split, recovery and total volume. Your rating is your own and is not calculated.') as item
    from v_weak_point_attention a where a.direct_sets_28d < 12) q $$;

create function api_next_targets(p_exercise_ids uuid[], p_on date default null) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform pfs_require_owner();
  return jsonb_build_object('data', jsonb_build_object('suggestions', pfs_next_targets(p_exercise_ids, coalesce(p_on, pfs_local_today()))), 'meta', pfs_meta());
end $$;
create function api_readiness(p_on date default null) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform pfs_require_owner();
  return jsonb_build_object('data', pfs_readiness(coalesce(p_on, pfs_local_today())), 'meta', pfs_meta());
end $$;
create function api_deload_signals(p_on date default null) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform pfs_require_owner();
  return jsonb_build_object('data', pfs_deload_signals(coalesce(p_on, pfs_local_today())), 'meta', pfs_meta());
end $$;
create function api_exercise_alternatives(p_exercise_id uuid, p_limit integer default 5) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform pfs_require_owner();
  return jsonb_build_object('data', jsonb_build_object('alternatives', pfs_alternatives(p_exercise_id, least(greatest(coalesce(p_limit, 5), 1), 20), pfs_local_today())), 'meta', pfs_meta());
end $$;
create function api_weak_point_suggestions() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform pfs_require_owner();
  return jsonb_build_object('data', jsonb_build_object('muscles', pfs_weak_point_suggestions(pfs_local_today())), 'meta', pfs_meta());
end $$;

-- Re-checks records and achievements for a session (for example after sets synced late). Safe to repeat.
create function api_detect_prs(p_device_id uuid, p_session_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a int; b int;
begin
  perform pfs_require_device(p_device_id);
  perform pg_advisory_xact_lock(hashtext('pfs_write'));
  a := pfs_detect_prs(p_session_id); b := pfs_detect_achievements(p_session_id);
  return jsonb_build_object('data', jsonb_build_object('records_changed', a, 'achievements_added', b), 'meta', pfs_meta());
end $$;

-- One call for the Today screen: plan, readiness, warnings, suggestions and the summaries around them. Each part keeps its own value_kind.
create function api_daily_briefing(p_on date default null) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare d date := coalesce(p_on, pfs_local_today()); en record; planned uuid[]; tmpl text; split_name text; out jsonb;
begin
  perform pfs_require_owner();
  select * into en from schedule_entries where local_date = d and deleted_at is null;
  planned := array(select te.exercise_id from template_exercises te where te.template_version_id = en.template_version_id and te.deleted_at is null order by te.position);
  select name into tmpl from template_versions where id = en.template_version_id;
  select sv.name into split_name from splits sp join split_versions sv on sv.entity_id = sp.id and sv.effective_to is null and sv.deleted_at is null
   where sp.status = 'active' and sp.deleted_at is null limit 1;
  out := jsonb_build_object(
    'date', d,
    'plan', jsonb_build_object('status', en.status, 'is_rest_day', en.is_rest_day, 'template_version_id', en.template_version_id, 'template_name', tmpl,
      'planned_exercises', cardinality(planned), 'is_break_day', pfs_is_break_day(d), 'active_split', split_name),
    'readiness', pfs_readiness(d),
    'restriction_warnings', api_restriction_warnings(planned, d) -> 'data' -> 'warnings',
    'next_targets', pfs_next_targets(planned, d),
    'supplements_today', coalesce((select jsonb_agg(jsonb_build_object('supplement_id', s.id, 'name', s.name, 'expected_doses', p.times_per_day,
        'taken_today', (select count(*) from supplement_logs l where l.supplement_id = s.id and l.local_date = d and l.outcome = 'taken' and l.deleted_at is null)) order by s.name)
      from supplements s join supplement_phases p on p.entity_id = s.id and p.effective_to is null and p.deleted_at is null and p.status = 'active'
      where s.deleted_at is null and (cardinality(p.days_of_week) = 0 or extract(isodow from d)::int = any (p.days_of_week))), '[]'::jsonb),
    'hydration', (select to_jsonb(h) from v_daily_hydration h where h.local_date = d),
    'water_target_ml', (pfs_target_on(d)).water_ml,
    'nutrition', (select to_jsonb(n) from v_daily_nutrition n where n.local_date = d),
    'steps', jsonb_build_object('steps', (select steps from daily_steps where local_date = d and deleted_at is null),
      'target', coalesce((select target_steps from daily_steps where local_date = d and deleted_at is null), (pfs_target_on(d)).step_target)),
    'reassessment', (select to_jsonb(r) from v_reassessment_due r),
    'deload', pfs_deload_signals(d) - 'inputs',
    'goals', coalesce((select jsonb_object_agg(progress_status, n) from (select progress_status, count(*) as n from v_goal_progress where goal_status = 'active' group by progress_status) g), '{}'::jsonb),
    'streak', (select to_jsonb(k) from v_current_streak k),
    'recent_records', coalesce((select jsonb_agg(jsonb_build_object('kind', r.kind, 'exercise', e.name, 'value', r.value, 'achieved_on', r.achieved_on) order by r.achieved_on desc)
      from (select * from personal_records where achieved_on >= d - 7 and achieved_on <= d order by achieved_on desc, rev desc limit 5) r left join exercises e on e.id = r.exercise_id), '[]'::jsonb),
    'trends', coalesce((select jsonb_agg(jsonb_build_object('exercise', e.name, 'signal', t.signal, 'change_pct', t.change_pct, 'value_kind', 'observation') order by e.name)
      from v_exercise_trends t join exercises e on e.id = t.exercise_id where t.signal in ('plateau', 'declining') and t.last_session_date >= d - 21), '[]'::jsonb),
    'weak_points', pfs_weak_point_suggestions(d));
  return jsonb_build_object('data', out, 'meta', pfs_meta());
end $$;

grant execute on function api_next_targets(uuid[], date), api_readiness(date), api_deload_signals(date), api_exercise_alternatives(uuid, integer),
  api_weak_point_suggestions(), api_detect_prs(uuid, uuid), api_daily_briefing(date) to authenticated;
