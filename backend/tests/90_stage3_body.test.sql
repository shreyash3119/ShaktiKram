-- Stage 3: measurements, body composition, check-ins, sleep, steps, cardio.
begin;
do $$
declare c record; n integer;
begin
  -- measurement rules
  perform t_expect_error($q$insert into body_measurements (occurred_at, local_date, tz_offset_minutes, measurement_type, value) values ('2026-10-05T01:00:00Z', '2026-10-05', 330, 'body_fat', 20)$q$, 'ck_body_measurements_body_fat_has_method');
  perform t_expect_error($q$insert into body_measurements (occurred_at, local_date, tz_offset_minutes, measurement_type, value, method) values ('2026-10-05T01:00:00Z', '2026-10-05', 330, 'body_fat', 120, 'manual')$q$, 'ck_body_measurements_body_fat_range');
  perform t_expect_error($q$insert into body_measurements (occurred_at, local_date, tz_offset_minutes, measurement_type, value) values ('2026-10-05T01:00:00Z', '2026-10-05', 330, 'custom', 5)$q$, 'ck_body_measurements_custom_has_label');
  perform t_expect_error($q$insert into body_measurements (occurred_at, local_date, tz_offset_minutes, measurement_type, value) values ('2026-10-05T01:00:00Z', '2026-10-05', 330, 'weight', 0)$q$, 'ck_body_measurements_value_positive');
  perform t_expect_error($q$insert into body_measurements (occurred_at, local_date, tz_offset_minutes, measurement_type, value) values ('2026-10-05T01:00:00Z', '2026-10-05', 330, 'height', 5)$q$, 'ck_body_measurements_measurement_type_values');

  insert into body_measurements (occurred_at, local_date, tz_offset_minutes, measurement_type, value, method) values
    ('2026-10-05T01:00:00Z', '2026-10-05', 330, 'weight', 80.0, null),
    ('2026-10-05T01:05:00Z', '2026-10-05', 330, 'body_fat', 20, 'smart_scale_bia'),
    ('2026-10-05T02:00:00Z', '2026-10-05', 330, 'body_fat', 18, 'skinfold'),
    ('2026-10-12T01:00:00Z', '2026-10-12', 330, 'body_fat', 19, 'manual'),
    ('2026-10-20T01:00:00Z', '2026-10-20', 330, 'weight', 79.5, null);
  select * into c from v_body_composition where local_date = '2026-10-05' and method = 'smart_scale_bia';
  assert c.fat_mass_kg = 16.00 and c.lean_mass_kg = 64.00 and c.value_kind = 'estimated', format('composition: %s', to_jsonb(c));
  select * into c from v_body_composition where local_date = '2026-10-05' and method = 'skinfold';
  assert c.fat_mass_kg = 14.40 and c.lean_mass_kg = 65.60, 'a different method is a separate reading';
  assert (select fat_mass_kg from v_body_composition where local_date = '2026-10-12') is null, 'no weight that day, no fat mass from body fat alone';
  assert (select count(*) from v_body_composition) = 3, 'one row per body-fat reading';
  assert (select value from v_measurement_latest where measurement_type = 'weight') = 79.5, 'latest weight';
  assert (select count(*) from v_measurement_latest where measurement_type = 'body_fat') = 3, 'latest body fat kept per method';

  -- daily check-in
  insert into daily_checkins (local_date, energy, sleep_quality, soreness, fatigue, motivation, stress, pain_flag) values ('2026-10-05', 4, 4, 2, 2, 5, 1, false);
  perform t_expect_error($q$insert into daily_checkins (local_date) values ('2026-10-05')$q$, 'uq_daily_checkins_local_date');
  perform t_expect_error($q$insert into daily_checkins (local_date, energy) values ('2026-10-06', 6)$q$, 'ck_daily_checkins_energy');
  insert into daily_checkins (local_date, notes) values ('2026-10-07', 'quick entry with no scores');

  -- sleep
  insert into sleep_logs (local_date, sleep_at, wake_at, duration_s, quality) values
    ('2026-10-06', '2026-10-05T17:30:00Z', '2026-10-06T00:30:00Z', 25200, 4),
    ('2026-10-07', '2026-10-06T17:30:00Z', '2026-10-07T01:30:00Z', 28800, 5),
    ('2026-10-08', '2026-10-07T18:00:00Z', '2026-10-08T00:00:00Z', 21600, 3);
  insert into sleep_logs (local_date, duration_s, is_nap) values ('2026-10-08', 1800, true);
  select * into c from v_sleep_weekly where week_start = '2026-10-05';
  assert c.nights = 3 and c.avg_duration_s = 25200 and c.avg_quality = 4.0 and c.bedtime_spread_min = 14, format('sleep week: %s', to_jsonb(c));
  perform t_expect_error($q$insert into sleep_logs (local_date, sleep_at, wake_at, duration_s) values ('2026-10-09', '2026-10-09T10:00:00Z', '2026-10-09T09:00:00Z', 3600)$q$, 'ck_sleep_logs_wake_after_sleep');
  perform t_expect_error($q$insert into sleep_logs (local_date, duration_s) values ('2026-10-09', 0)$q$, 'ck_sleep_logs_duration');

  -- steps
  insert into daily_steps (local_date, steps, target_steps) values ('2026-10-05', 8000, 10000), ('2026-10-06', 12000, 10000);
  select * into c from v_steps_weekly where week_start = '2026-10-05';
  assert c.days_logged = 2 and c.avg_steps = 10000 and c.max_steps = 12000 and c.days_on_target = 1, format('steps week: %s', to_jsonb(c));
  perform t_expect_error($q$insert into daily_steps (local_date, steps) values ('2026-10-05', 1)$q$, 'uq_daily_steps_local_date');

  -- cardio
  insert into cardio_sessions (occurred_at, local_date, tz_offset_minutes, activity, duration_s, distance_m, incline_pct, intensity) values
    ('2026-10-06T12:00:00Z', '2026-10-06', 330, 'treadmill', 1800, 5000, 2.0, 'moderate'),
    ('2026-10-07T12:00:00Z', '2026-10-07', 330, 'walking', 1200, 3000, null, 'low'),
    ('2026-10-08T12:00:00Z', '2026-10-08', 330, 'stairmaster', 600, null, null, 'high');
  select * into c from v_cardio_weekly where week_start = '2026-10-05';
  assert c.sessions = 3 and c.total_duration_s = 3600 and c.total_distance_m = 8000 and c.avg_pace_s_per_km = 375, format('cardio week: %s', to_jsonb(c));
  perform t_expect_error($q$insert into cardio_sessions (occurred_at, local_date, tz_offset_minutes, activity, duration_s) values ('2026-10-09T12:00:00Z', '2026-10-09', 330, 'custom', 600)$q$, 'ck_cardio_sessions_custom_has_name');
end $$;
rollback;
