-- Stage 4 / the calculation rules, written once. Plain-language specs: shared/calculation_specs/. Test cases: shared/test_vectors/.
-- Every calc_* function takes one jsonb object and returns one jsonb object, so the phone (Dart) can run the same test cases.
-- Results are suggestions or observations. Nothing here diagnoses or gives medical advice.

-- Estimated one-rep max (Epley). Only for 1 to 12 reps; more reps make the estimate unreliable, so there is none.
create function pfs_e1rm(p_weight numeric, p_reps integer) returns numeric language sql immutable as $$
  select case when p_weight is null or p_reps is null or p_weight <= 0 or p_reps < 1 or p_reps > 12 then null
              when p_reps = 1 then round(p_weight, 2)
              else round(p_weight * (1 + p_reps / 30.0), 2) end $$;
create function calc_e1rm(p jsonb) returns jsonb language sql immutable as $$
  select jsonb_build_object('e1rm_kg', pfs_e1rm((p ->> 'weight_kg')::numeric, (p ->> 'reps')::integer)) $$;

-- Next-session suggestion (double progression). Input: last session's completed working sets and the prescription.
create function calc_progression(p jsonb) returns jsonb language plpgsql immutable as $$
declare
  v_sets jsonb := coalesce(p -> 'sets', '[]'::jsonb);
  rmin int := coalesce((p ->> 'rep_min')::int, 8); rmax int := coalesce((p ->> 'rep_max')::int, 12);
  tsets int := coalesce((p ->> 'target_sets')::int, 3); inc numeric := coalesce((p ->> 'increment_kg')::numeric, 2.5);
  w numeric; n_at_w int; min_reps int; effort_high boolean;
  v_action text; v_weight numeric; v_reps int; v_code text; v_why text;
begin
  if coalesce((p ->> 'restricted')::boolean, false) then
    v_action := 'review'; v_code := 'restriction_active';
    v_why := 'A restriction you recorded applies to this exercise. Review or modify it before choosing a load.';
  elsif jsonb_array_length(v_sets) = 0 then
    v_action := 'no_history'; v_code := 'no_history'; v_why := 'No completed working sets are logged for this exercise yet.';
  else
    select x.wt into w from (select (e ->> 'weight_kg')::numeric as wt from jsonb_array_elements(v_sets) e) x
      group by x.wt order by count(*) desc, x.wt desc limit 1;
    select count(*), min((e ->> 'reps')::int), bool_or(coalesce((e ->> 'rir')::numeric, 99) = 0 or coalesce((e ->> 'rpe')::numeric, 0) >= 9.5)
      into n_at_w, min_reps, effort_high from jsonb_array_elements(v_sets) e where (e ->> 'weight_kg')::numeric = w;
    if coalesce((p ->> 'deload_active')::boolean, false) then
      v_action := 'deload'; v_weight := round(w * 0.9 / inc) * inc; v_reps := rmin; v_code := 'deload_period';
      v_why := 'A deload period is recorded for today, so a lighter load is shown. You decide what to change.';
    elsif n_at_w < tsets then
      v_action := 'repeat'; v_weight := w; v_reps := least(rmax, min_reps); v_code := 'incomplete_sets';
      v_why := format('Fewer than %s working sets were completed at %s kg, so the same load is suggested.', tsets, w);
    elsif min_reps < rmin then
      v_action := 'repeat'; v_weight := w; v_reps := rmin; v_code := 'below_rep_range';
      v_why := format('Reps fell below %s on at least one set at %s kg, so the same load is suggested.', rmin, w);
    elsif effort_high then
      v_action := 'repeat'; v_weight := w; v_reps := least(rmax, min_reps); v_code := 'effort_very_high';
      v_why := 'Effort was already very high (no reps left in reserve), so the same load is suggested.';
    elsif min_reps >= rmax then
      v_action := 'increase'; v_weight := w + inc; v_reps := rmin; v_code := 'top_of_range_all_sets';
      v_why := format('All %s sets reached %s reps at %s kg, so a small increase is suggested.', tsets, rmax, w);
    else
      v_action := 'add_reps'; v_weight := w; v_reps := least(rmax, min_reps + 1); v_code := 'within_range';
      v_why := format('Reps are inside the %s-%s range, so the aim is one more rep at %s kg.', rmin, rmax, w);
    end if;
  end if;
  return jsonb_build_object('action', v_action, 'suggested_weight_kg', v_weight, 'target_reps', v_reps,
    'reason_codes', jsonb_build_array(v_code), 'reasoning', jsonb_build_array(v_why), 'value_kind', 'suggestion',
    'based_on', jsonb_build_object('working_weight_kg', w, 'sets_at_weight', n_at_w, 'min_reps', min_reps));
end $$;

-- Trend of an exercise from the best estimated 1RM of its recent sessions (oldest first). Needs at least 4 sessions.
create function calc_trend(p jsonb) returns jsonb language plpgsql immutable as $$
declare s numeric[]; first_v numeric; last_v numeric; mx numeric; chg numeric; sig text;
begin
  select array_agg(x::numeric order by ord) into s from jsonb_array_elements_text(coalesce(p -> 'series', '[]'::jsonb)) with ordinality t(x, ord);
  if s is null or cardinality(s) < 4 or s[1] <= 0 then
    return jsonb_build_object('signal', 'insufficient_data', 'change_pct', null, 'value_kind', 'observation');
  end if;
  first_v := s[1]; last_v := s[cardinality(s)]; select max(v) into mx from unnest(s) v;
  chg := round((last_v - first_v) / first_v * 100, 1);
  sig := case when last_v < mx * 0.95 then 'declining' when chg >= 1.0 then 'improving' else 'plateau' end;
  return jsonb_build_object('signal', sig, 'change_pct', chg, 'value_kind', 'observation');
end $$;

-- Readiness summary from a check-in and context. Decision support only.
create function calc_readiness(p jsonb) returns jsonb language plpgsql immutable as $$
declare
  k text; v numeric; total numeric := 0; cnt int := 0; wellness numeric; lvl text;
  has_checkin boolean := coalesce((p ->> 'has_checkin')::boolean, false); pain_flag boolean := coalesce((p ->> 'pain_flag')::boolean, false);
  pain numeric := (p ->> 'max_pain_level')::numeric; sleep_h numeric := (p ->> 'sleep_hours')::numeric;
  review_codes text[] := '{}'; light_codes text[] := '{}'; why text[] := '{}';
begin
  foreach k in array array['energy', 'sleep_quality', 'motivation'] loop v := (p ->> k)::numeric; if v is not null then total := total + v; cnt := cnt + 1; end if; end loop;
  foreach k in array array['soreness', 'fatigue', 'stress'] loop v := (p ->> k)::numeric; if v is not null then total := total + (6 - v); cnt := cnt + 1; end if; end loop;
  if cnt >= 3 then wellness := round(total / cnt, 1); end if;
  if coalesce((p ->> 'suggest_professional_review')::boolean, false) then
    review_codes := array_append(review_codes, 'injury_review_flag'::text); why := why || 'An injury you recorded is flagged for review. Consider having it assessed by a professional.'::text;
  end if;
  if pain >= 7 then review_codes := array_append(review_codes, 'high_pain'::text); why := why || 'You reported pain of 7 or more recently. Review the symptoms before training.'::text;
  elsif pain_flag and pain >= 5 then review_codes := array_append(review_codes, 'pain_reported'::text); why := why || 'You reported pain or discomfort. Review the symptoms before training.'::text; end if;
  if wellness < 2.5 then light_codes := array_append(light_codes, 'low_wellness'::text); why := why || 'Your check-in answers are on the low side overall.'::text; end if;
  if sleep_h < 5 then light_codes := array_append(light_codes, 'short_sleep'::text); why := why || 'You slept under 5 hours.'::text; end if;
  if (p ->> 'soreness')::numeric >= 4 then light_codes := array_append(light_codes, 'high_soreness'::text); why := why || 'Soreness is high.'::text; end if;
  if (p ->> 'fatigue')::numeric >= 4 then light_codes := array_append(light_codes, 'high_fatigue'::text); why := why || 'Fatigue is high.'::text; end if;
  lvl := case when cardinality(review_codes) > 0 then 'review' when cardinality(light_codes) > 0 then 'lighter'
              when not has_checkin then 'no_checkin' when wellness is null then 'limited_data' else 'proceed' end;
  if lvl = 'proceed' then why := why || 'Your check-in looks reasonable. Adjust as you go based on how the warm-up feels.'::text; end if;
  if lvl = 'no_checkin' then why := why || 'No check-in yet today. A quick check-in gives a better summary.'::text; end if;
  if lvl = 'limited_data' then why := why || 'Too few check-in answers for a summary.'::text; end if;
  return jsonb_build_object('level', lvl, 'wellness_score', wellness, 'reason_codes', to_jsonb(review_codes || light_codes), 'reasoning', to_jsonb(why),
    'value_kind', 'suggestion', 'note', 'Decision support only. This is not medical advice and not a guarantee that training is safe.');
end $$;

-- Patterns that may justify considering a deload. It never says a deload is necessary.
create function calc_deload_signal(p jsonb) returns jsonb language plpgsql immutable as $$
declare codes text[] := '{}'; why text[] := '{}'; lvl text;
begin
  if (p ->> 'weeks_since_deload')::numeric >= 6 then codes := array_append(codes, 'long_block'::text); why := why || 'Six or more weeks of training since the last deload.'::text; end if;
  if coalesce((p ->> 'fatigue_entries')::int, 0) >= 5 and (p ->> 'fatigue_high_count')::numeric / (p ->> 'fatigue_entries')::numeric >= 0.5 then
    codes := array_append(codes, 'persistent_fatigue'::text); why := why || 'Fatigue was high in at least half of your recent check-ins.'::text; end if;
  if coalesce((p ->> 'soreness_entries')::int, 0) >= 5 and (p ->> 'soreness_high_count')::numeric / (p ->> 'soreness_entries')::numeric >= 0.5 then
    codes := array_append(codes, 'persistent_soreness'::text); why := why || 'Soreness was high in at least half of your recent check-ins.'::text; end if;
  if coalesce((p ->> 'declining_exercises')::int, 0) >= 2 then codes := array_append(codes, 'performance_decline'::text); why := why || 'Two or more exercises show lower recent performance.'::text; end if;
  if coalesce((p ->> 'sleep_nights')::int, 0) >= 4 and (p ->> 'avg_sleep_h')::numeric < 6 then codes := array_append(codes, 'short_sleep'::text); why := why || 'Average sleep over the last week was under 6 hours.'::text; end if;
  lvl := case when cardinality(codes) = 0 then 'none' when cardinality(codes) = 1 then 'watch' else 'consider_reviewing_deload' end;
  return jsonb_build_object('level', lvl, 'reason_codes', to_jsonb(codes), 'reasoning', to_jsonb(why), 'value_kind', 'suggestion',
    'note', 'These are observations from your records. Whether to schedule a deload is your decision.');
end $$;

-- Progress of a goal between a start value and a target value, compared with the time used.
create function calc_goal_progress(p jsonb) returns jsonb language plpgsql immutable as $$
declare
  s numeric := (p ->> 'start_value')::numeric; c numeric := (p ->> 'current_value')::numeric; t numeric := (p ->> 'target_value')::numeric;
  sd date := (p ->> 'start_date')::date; td date := (p ->> 'target_date')::date; today date := (p ->> 'today')::date;
  pct numeric; reached boolean; el numeric; st text;
begin
  if s is null or c is null or t is null or s = t then
    return jsonb_build_object('progress_pct', null, 'status', 'insufficient_data', 'reached', false, 'expected_pct', null);
  end if;
  pct := round((c - s) / (t - s) * 100, 1);
  reached := case when t > s then c >= t else c <= t end;
  if reached then st := 'reached';
  elsif td is null or sd is null or today is null then st := 'no_deadline';
  elsif today > td then st := 'overdue';
  elsif td <= sd then st := 'insufficient_data';
  else
    el := least(100, greatest(0, (today - sd)::numeric / (td - sd) * 100));
    st := case when pct >= el + 10 then 'ahead' when pct >= el - 10 then 'on_track' else 'behind' end;
  end if;
  return jsonb_build_object('progress_pct', pct, 'status', st, 'reached', reached, 'expected_pct', round(el, 1));
end $$;

-- Completed working sets with the facts the rules need (RLS still applies to the caller).
create view v_working_sets with (security_invoker = true) as
select st.id as set_id, se.session_id, se.exercise_id, s.occurred_at as session_occurred_at, s.local_date as session_local_date, s.status as session_status,
  st.weight_kg, st.reps, st.rir, st.rpe, st.occurred_at as set_occurred_at
from sets st
join session_exercises se on se.id = st.session_exercise_id and se.deleted_at is null and se.status <> 'skipped'
join workout_sessions s on s.id = se.session_id and s.deleted_at is null and s.status <> 'abandoned'
where st.deleted_at is null and st.set_type = 'working' and st.completed and st.weight_kg is not null and st.reps is not null and st.reps >= 1;
