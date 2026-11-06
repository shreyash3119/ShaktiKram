-- Stage 1 / profile (versioned), settings (single row), goals with status history, reminder rules.

create table profile_versions (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  entity_id uuid not null, version integer not null,
  effective_from timestamptz not null, effective_to timestamptz,
  previous_version_id uuid references profile_versions (id), change_reason text,
  date_of_birth date,
  height_cm numeric(5,1),
  body_weight_kg numeric(6,2),
  experience_level text,
  training_history_notes text,
  preferred_workout_days smallint[] not null default '{}',
  preferred_workout_time time,
  training_preferences text,
  preferences jsonb not null default '{}'::jsonb,
  constraint ck_profile_versions_version_positive check (version >= 1),
  constraint ck_profile_versions_interval check (effective_to is null or effective_to >= effective_from),
  constraint ck_profile_versions_height_positive check (height_cm is null or height_cm > 0),
  constraint ck_profile_versions_weight_positive check (body_weight_kg is null or body_weight_kg > 0),
  constraint ck_profile_versions_days check (preferred_workout_days <@ array[1,2,3,4,5,6,7]::smallint[]),
  constraint uq_profile_versions_entity_id_version unique (entity_id, version),
  constraint ex_profile_versions_no_overlap exclude using gist (entity_id with =, tstzrange(effective_from, effective_to, '[)') with &&)
);
-- One personal profile: only one version may be current at a time.
create unique index uq_profile_versions_one_current on profile_versions ((true)) where effective_to is null and deleted_at is null;
select pfs_attach('profile_versions', 'versioned', true);

create table settings (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  singleton boolean not null default true,
  weight_unit text not null default 'kg', length_unit text not null default 'cm', distance_unit text not null default 'km',
  week_start text not null default 'monday',
  time_zone text not null default 'Asia/Kolkata',
  reassessment_interval_days integer not null default 14,
  notification_prefs jsonb not null default '{}'::jsonb,
  dashboard_prefs jsonb not null default '{}'::jsonb,
  constraint uq_settings_singleton unique (singleton),
  constraint ck_settings_singleton check (singleton),
  constraint ck_settings_reassessment_interval_positive check (reassessment_interval_days >= 1)
);
create function pfs_validate_settings() returns trigger language plpgsql as $$
begin
  perform (now() at time zone new.time_zone);
  return new;
exception when invalid_parameter_value then
  raise exception 'validation_failed: unknown time zone %', new.time_zone;
end $$;
create trigger d_settings_validate before insert or update on settings for each row execute function pfs_validate_settings();
select pfs_attach('settings', 'editable', true);
insert into settings (id) values (md5('settings_singleton')::uuid);

create table goals (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  type text not null, title text not null, description text,
  target_metric text, target_value numeric(10,2), target_unit text,
  start_date date not null default current_date, intended_duration_days integer, target_date date,
  status text not null default 'active', notes text,
  constraint ck_goals_title_not_blank check (length(trim(title)) > 0),
  constraint ck_goals_duration_positive check (intended_duration_days is null or intended_duration_days > 0),
  constraint ck_goals_dates check (target_date is null or target_date >= start_date)
);
select pfs_attach('goals', 'editable', true);

-- Status timeline. Written by a trigger on goals so it cannot be skipped by a client.
create table goal_status_events (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  goal_id uuid not null references goals (id),
  status text not null, reason text,
  occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null
);
create index idx_goal_status_events_goal_id on goal_status_events (goal_id, occurred_at);
select pfs_attach('goal_status_events', 'append_only', false, true, false);

create function pfs_goal_status_event() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare tz text; off integer; t timestamptz := now();
begin
  if pfs_restore_allowed() then return null; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then return null; end if;
  select time_zone into tz from settings limit 1;
  tz := coalesce(tz, 'UTC');
  off := (extract(epoch from ((t at time zone tz) - (t at time zone 'UTC'))) / 60)::integer;
  insert into goal_status_events (goal_id, status, reason, occurred_at, local_date, tz_offset_minutes)
  values (new.id, new.status, nullif(current_setting('pfs.reason', true), ''), t,
          ((t at time zone 'UTC') + make_interval(mins => off))::date, off);
  return null;
end $$;
create trigger y_goal_status_event after insert or update on goals for each row execute function pfs_goal_status_event();

-- Rules only. The backend stores them; delivery is local scheduled notifications on the device (decision D10).
-- schedule format: {"type":"daily|weekly","time":"HH:MM","days":[1..7]} (ISO weekdays), refined in Stage 3.
create table reminder_rules (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  kind text not null, label text not null,
  schedule jsonb not null default '{}'::jsonb,
  is_enabled boolean not null default true,
  paused_until date,
  linked_table text, linked_record_id uuid
);
select pfs_attach('reminder_rules', 'editable');
