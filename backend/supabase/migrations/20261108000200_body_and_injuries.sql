-- Stage 3 / body measurements, injuries, pain entries, exercise restrictions.
-- Observations only: nothing here diagnoses or prescribes (contract section 12).

-- One row per reading. Implied units: weight and muscle_mass in kg, body_fat in percent, lengths in cm.
create table body_measurements (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null,
  measurement_type text not null, value numeric(8,2) not null,
  custom_label text, custom_unit text, side text,
  method text, source text not null default 'manual', notes text,
  constraint ck_body_measurements_value_positive check (value > 0),
  constraint ck_body_measurements_body_fat_range check (measurement_type <> 'body_fat' or value < 100),
  constraint ck_body_measurements_body_fat_has_method check (measurement_type <> 'body_fat' or method is not null),
  constraint ck_body_measurements_custom_has_label check (measurement_type <> 'custom' or (custom_label is not null and custom_unit is not null))
);
create index idx_body_measurements_type_date on body_measurements (measurement_type, local_date);
select pfs_attach('body_measurements', 'append_only', false, true);

create table injuries (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  name text not null, body_region_id uuid not null references body_regions (id), side text not null default 'not_applicable',
  injury_type text, start_date date not null, severity text, status text not null default 'active',
  description text, notes text, resolved_on date,
  constraint ck_injuries_name_not_blank check (length(trim(name)) > 0),
  constraint ck_injuries_resolved_after_start check (resolved_on is null or resolved_on >= start_date),
  constraint ck_injuries_resolved_has_date check (status <> 'resolved' or resolved_on is not null)
);
create index idx_injuries_body_region_id on injuries (body_region_id);
create index idx_injuries_status on injuries (status);
select pfs_attach('injuries', 'editable', true);

-- Recovery timeline: follow-up notes and status changes. Never deleted when an injury is resolved.
create table injury_updates (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  injury_id uuid not null references injuries (id),
  note text, severity text, status text,
  occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null,
  constraint ck_injury_updates_has_content check (note is not null or severity is not null or status is not null)
);
create index idx_injury_updates_injury_id on injury_updates (injury_id, occurred_at);
select pfs_attach('injury_updates', 'append_only', false, true);

-- Pain and discomfort check-in. Kept apart from ordinary muscle soreness (which lives in daily_checkins).
create table pain_entries (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  body_region_id uuid not null references body_regions (id), side text not null default 'not_applicable',
  level smallint not null, pain_type text, effect_on_training text not null default 'none',
  injury_id uuid references injuries (id), checkin_id uuid references daily_checkins (id), notes text,
  occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null,
  constraint ck_pain_entries_level check (level >= 0 and level <= 10)
);
create index idx_pain_entries_injury_id on pain_entries (injury_id, occurred_at);
create index idx_pain_entries_body_region_id on pain_entries (body_region_id);
select pfs_attach('pain_entries', 'append_only', false, true);

-- Movements that trigger discomfort, or that the user was advised to avoid or modify. Matched to a planned exercise by exercise_id.
-- A movement-only restriction (exercise_id empty) is kept as a note; matching it to exercises is left to the client.
create table exercise_restrictions (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  injury_id uuid references injuries (id), exercise_id uuid references exercises (id), movement text,
  kind text not null, source text not null default 'self', note text,
  active_from date not null default current_date, active_to date,
  constraint ck_exercise_restrictions_target check (exercise_id is not null or movement is not null),
  constraint ck_exercise_restrictions_dates check (active_to is null or active_to >= active_from)
);
create index idx_exercise_restrictions_exercise_id on exercise_restrictions (exercise_id);
select pfs_attach('exercise_restrictions', 'editable', true);
