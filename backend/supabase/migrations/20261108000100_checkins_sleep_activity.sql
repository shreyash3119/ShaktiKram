-- Stage 3 / daily check-in, sleep, steps and cardio.

create table daily_checkins (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  local_date date not null,
  energy smallint, sleep_quality smallint, soreness smallint, fatigue smallint, motivation smallint, stress smallint,
  pain_flag boolean not null default false, notes text,
  constraint ck_daily_checkins_energy check (energy is null or (energy >= 1 and energy <= 5)),
  constraint ck_daily_checkins_sleep_quality check (sleep_quality is null or (sleep_quality >= 1 and sleep_quality <= 5)),
  constraint ck_daily_checkins_soreness check (soreness is null or (soreness >= 1 and soreness <= 5)),
  constraint ck_daily_checkins_fatigue check (fatigue is null or (fatigue >= 1 and fatigue <= 5)),
  constraint ck_daily_checkins_motivation check (motivation is null or (motivation >= 1 and motivation <= 5)),
  constraint ck_daily_checkins_stress check (stress is null or (stress >= 1 and stress <= 5))
);
create unique index uq_daily_checkins_local_date on daily_checkins (local_date) where deleted_at is null;
select pfs_attach('daily_checkins', 'editable');

create table sleep_logs (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  local_date date not null,                          -- the day you woke up
  sleep_at timestamptz, wake_at timestamptz,
  duration_s integer not null, quality smallint, is_nap boolean not null default false, notes text,
  constraint ck_sleep_logs_duration check (duration_s > 0 and duration_s <= 86400),
  constraint ck_sleep_logs_quality check (quality is null or (quality >= 1 and quality <= 5)),
  constraint ck_sleep_logs_wake_after_sleep check (sleep_at is null or wake_at is null or wake_at > sleep_at)
);
create index idx_sleep_logs_local_date on sleep_logs (local_date);
select pfs_attach('sleep_logs', 'editable');

create table daily_steps (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  local_date date not null, steps integer not null, target_steps integer, source text not null default 'manual',
  constraint ck_daily_steps_steps_nonnegative check (steps >= 0),
  constraint ck_daily_steps_target_positive check (target_steps is null or target_steps > 0)
);
create unique index uq_daily_steps_local_date on daily_steps (local_date) where deleted_at is null;
select pfs_attach('daily_steps', 'editable');

create table cardio_sessions (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null,
  activity text not null, custom_activity text,
  duration_s integer not null, distance_m numeric(9,1), avg_speed_mps numeric(5,2), incline_pct numeric(4,1),
  calories_kcal numeric(7,1), avg_heart_rate_bpm smallint, max_heart_rate_bpm smallint,
  intensity text, source text not null default 'manual', notes text,
  constraint ck_cardio_sessions_duration_positive check (duration_s > 0),
  constraint ck_cardio_sessions_distance_nonnegative check (distance_m is null or distance_m >= 0),
  constraint ck_cardio_sessions_speed_nonnegative check (avg_speed_mps is null or avg_speed_mps >= 0),
  constraint ck_cardio_sessions_calories_nonnegative check (calories_kcal is null or calories_kcal >= 0),
  constraint ck_cardio_sessions_custom_has_name check (activity <> 'custom' or custom_activity is not null)
);
create index idx_cardio_sessions_local_date on cardio_sessions (local_date);
select pfs_attach('cardio_sessions', 'append_only', false, true);
