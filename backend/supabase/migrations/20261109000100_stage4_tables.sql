-- Stage 4 / tables for the intelligence layer: technique library, media, equipment status, personal records, achievements,
-- deloads, goal progress and milestones. Calculated results are not stored by hand: records and achievements are written by the database.

alter table exercises add column weight_increment_kg numeric(5,2) not null default 2.5,
  add constraint ck_exercises_increment_positive check (weight_increment_kg > 0);

create table exercise_reference (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  exercise_id uuid not null references exercises (id),
  instructions text, form_notes text, common_mistakes text, personal_difficulty smallint, notes text,
  constraint ck_exercise_reference_personal_difficulty check (personal_difficulty is null or (personal_difficulty >= 1 and personal_difficulty <= 5))
);
create unique index uq_exercise_reference_exercise_id on exercise_reference (exercise_id) where deleted_at is null;
select pfs_attach('exercise_reference', 'editable');

-- The file itself lives in the private `media` bucket; this row points to it. Upload recovery is Stage 6.
create table media_assets (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  owner_table text not null, owner_id uuid not null,
  file_ref text not null, media_type text not null, title text, content_hash text, notes text
);
create index idx_media_assets_owner on media_assets (owner_table, owner_id);
select pfs_attach('media_assets', 'editable');

create table equipment_status_events (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  equipment_id uuid not null references equipment (id),
  status text not null, note text,
  occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null
);
create index idx_equipment_status_events_equipment_id on equipment_status_events (equipment_id, occurred_at);
select pfs_attach('equipment_status_events', 'append_only', false, true);

-- Written by the database when a session is completed. Kept as history even if a supporting set is corrected later.
create table personal_records (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  exercise_id uuid references exercises (id),            -- empty for workout_volume
  kind text not null, value numeric(12,2) not null,
  weight_kg numeric(6,2), reps smallint, previous_value numeric(12,2),
  session_id uuid not null references workout_sessions (id), set_id uuid references sets (id), achieved_on date not null
);
create unique index uq_personal_records_per_session on personal_records
  (session_id, kind, coalesce(exercise_id, '00000000-0000-0000-0000-000000000000'::uuid), (coalesce(case when kind = 'best_reps_at_weight' then weight_kg end, -1)));
create index idx_personal_records_exercise_id on personal_records (exercise_id, achieved_on);
select pfs_attach('personal_records', 'append_only', false, false, false);

create table achievements (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  kind text not null, threshold integer not null, title text not null, achieved_on date not null,
  supporting_table text, supporting_record_id uuid
);
create unique index uq_achievements_kind_threshold on achievements (kind, threshold);
select pfs_attach('achievements', 'append_only', false, false, false);

create table deload_periods (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  start_date date not null, end_date date not null, status text not null default 'planned',
  reason text, changes text, notes text,
  constraint ck_deload_periods_dates check (end_date >= start_date)
);
select pfs_attach('deload_periods', 'editable', true);

-- Manual progress entries for goals the app cannot measure on its own.
create table goal_progress (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  goal_id uuid not null references goals (id), local_date date not null, value numeric(12,2) not null, note text
);
create index idx_goal_progress_goal_id on goal_progress (goal_id, local_date);
select pfs_attach('goal_progress', 'append_only');

create table milestones (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  goal_id uuid not null references goals (id), title text not null, target_value numeric(12,2) not null, note text,
  constraint ck_milestones_title_not_blank check (length(trim(title)) > 0)
);
create index idx_milestones_goal_id on milestones (goal_id);
select pfs_attach('milestones', 'editable');
