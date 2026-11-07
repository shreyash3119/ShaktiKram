-- Stage 3 / muscle development assessment (feature 17).
-- Ratings are the user's own manual assessment. They are never calculated from weight, reps, sets or volume.

create table muscle_assessments (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null,
  notes text
);
create index idx_muscle_assessments_local_date on muscle_assessments (local_date);
select pfs_attach('muscle_assessments', 'append_only', false, true);

create table muscle_assessment_items (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  assessment_id uuid not null references muscle_assessments (id),
  muscle_id uuid not null references muscles (id),
  level smallint not null,
  constraint ck_muscle_assessment_items_level check (level >= 1 and level <= 5)
);
create unique index uq_muscle_assessment_items_alive on muscle_assessment_items (assessment_id, muscle_id) where deleted_at is null;
create index idx_muscle_assessment_items_muscle_id on muscle_assessment_items (muscle_id);
select pfs_attach('muscle_assessment_items', 'append_only');

-- Priority register, one entity per muscle (entity_id is the muscle id). 1 weak point, 2 maintenance, 3 lower priority.
create table muscle_priorities (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  entity_id uuid not null references muscles (id), version integer not null,
  effective_from timestamptz not null, effective_to timestamptz,
  previous_version_id uuid references muscle_priorities (id), change_reason text,
  priority smallint not null,
  constraint ck_muscle_priorities_priority check (priority >= 1 and priority <= 3),
  constraint ck_muscle_priorities_version_positive check (version >= 1),
  constraint ck_muscle_priorities_interval check (effective_to is null or effective_to >= effective_from),
  constraint uq_muscle_priorities_entity_id_version unique (entity_id, version),
  constraint ex_muscle_priorities_no_overlap exclude using gist (entity_id with =, tstzrange(effective_from, effective_to, '[)') with &&)
);
create unique index uq_muscle_priorities_one_current on muscle_priorities (entity_id) where effective_to is null and deleted_at is null;
select pfs_attach('muscle_priorities', 'versioned', true);

create table weak_point_events (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  muscle_id uuid not null references muscles (id),
  event text not null, exercise_id uuid references exercises (id), note text,
  occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null
);
create index idx_weak_point_events_muscle_id on weak_point_events (muscle_id, occurred_at);
select pfs_attach('weak_point_events', 'append_only', false, true);
