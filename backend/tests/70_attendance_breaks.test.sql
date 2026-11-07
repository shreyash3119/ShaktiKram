-- Attendance and breaks: breaks, rest days and rescheduled days are never counted as missed.
begin;
create function t_sess(p_date date) returns uuid language plpgsql as $$
declare v uuid := gen_random_uuid();
begin
  insert into workout_sessions (id, occurred_at, ended_at, local_date, tz_offset_minutes, status)
  values (v, (p_date::text || 'T12:00:00Z')::timestamptz, (p_date::text || 'T13:00:00Z')::timestamptz, p_date, 330, 'completed');
  return v;
end $$;
do $$
declare s1 uuid := t_sess('2026-10-05'); s2 uuid := t_sess('2026-10-10'); s3 uuid := t_sess('2026-10-13'); w record; k record;
begin
  insert into schedule_entries (local_date, status, session_id, is_rest_day, rescheduled_to, replaced_by_activity) values
    ('2026-10-05', 'completed', s1, false, null, null),
    ('2026-10-06', 'planned', null, true, null, null),
    ('2026-10-07', 'skipped', null, false, null, null),
    ('2026-10-08', 'skipped', null, false, null, null),
    ('2026-10-09', 'planned', null, false, null, null),
    ('2026-10-10', 'completed', s2, false, null, null),
    ('2026-10-11', 'replaced', null, false, null, 'football'),
    ('2026-10-12', 'rescheduled', null, false, '2026-10-13', null),
    ('2026-10-13', 'completed', s3, false, null, null),
    ('2099-01-01', 'planned', null, false, null, null);
  insert into planned_breaks (title, start_date, end_date, reason, mode, status) values
    ('Exams', '2026-10-08', '2026-10-09', 'exams_study', 'full', 'ended'),
    ('Cancelled trip', '2026-10-07', '2026-10-07', 'vacation_travel', 'full', 'cancelled'),
    ('Light week', '2026-10-11', '2026-10-11', 'personal', 'reduced', 'planned');

  assert pfs_is_break_day('2026-10-08') and not pfs_is_break_day('2026-10-07') and not pfs_is_break_day('2026-10-11'), 'only approved full or modified breaks excuse days';
  assert (select is_missed from v_attendance_daily where local_date = '2026-10-07'), 'skipped normal day is missed';
  assert not (select is_missed from v_attendance_daily where local_date = '2026-10-08'), 'skipped day inside a break is not missed';
  assert not (select is_missed from v_attendance_daily where local_date = '2026-10-09'), 'planned day inside a break is not missed';
  assert not (select is_missed from v_attendance_daily where local_date = '2026-10-06'), 'rest day is not missed';
  assert not (select is_missed from v_attendance_daily where local_date = '2026-10-12'), 'rescheduled original is not missed';
  assert not (select is_missed from v_attendance_daily where local_date = '2099-01-01'), 'future day is not missed';
  select * into w from v_consistency_weekly where week_start = '2026-10-05';
  assert w.scheduled = 4 and w.completed = 3 and w.missed = 1 and w.break_days = 2 and w.consistency_pct = 75.0, format('week 1: %s', to_jsonb(w));
  select * into w from v_consistency_weekly where week_start = '2026-10-12';
  assert w.scheduled = 1 and w.completed = 1 and w.consistency_pct = 100.0, format('week 2: %s', to_jsonb(w));
  select * into k from v_current_streak;
  assert k.current_streak = 3 and k.longest_streak = 3, format('streak: %s', to_jsonb(k));

  perform t_expect_error('insert into schedule_entries (local_date, status) values (''2026-12-01'', ''completed'')', 'ck_schedule_entries_completed_has_session');
  perform t_expect_error('insert into schedule_entries (local_date, status) values (''2026-12-02'', ''rescheduled'')', 'ck_schedule_entries_rescheduled_has_date');
  perform t_expect_error('insert into schedule_entries (local_date, status) values (''2026-12-03'', ''replaced'')', 'ck_schedule_entries_replaced_has_activity');
  perform t_expect_error('insert into schedule_entries (local_date) values (''2026-10-05'')', 'uq_schedule_entries_local_date');
  perform t_expect_error('insert into planned_breaks (title, start_date, end_date) values (''x'', ''2026-12-10'', ''2026-12-01'')', 'ck_planned_breaks_dates');
  perform t_expect_error('insert into planned_breaks (title, start_date, end_date, mode) values (''x'', ''2026-12-01'', ''2026-12-02'', ''nonsense'')', 'ck_planned_breaks_mode_values');
  perform t_expect_error('insert into break_events (break_id, event, occurred_at, local_date, tz_offset_minutes) select id, ''started'', ''2026-10-08T00:00:00Z'', ''2026-10-01'', 330 from planned_breaks limit 1', 'local_date does not match');
end $$;
rollback;
