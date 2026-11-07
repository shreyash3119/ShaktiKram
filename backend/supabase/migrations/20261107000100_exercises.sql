-- Stage 2 / exercise catalogue: extends the Stage 1 stub, adds muscle mapping and alternatives.

alter table exercises
  add column category text,
  add column equipment_id uuid references equipment (id),
  add column introduced_on date,
  add column removed_on date,
  add column notes text,
  add constraint ck_exercises_removed_after_introduced check (removed_on is null or introduced_on is null or removed_on >= introduced_on);
create unique index uq_exercises_name_alive on exercises (lower(name)) where deleted_at is null;
create index idx_exercises_equipment_id on exercises (equipment_id);

-- Which muscles an exercise trains. Feeds training exposure (Stage 4) and alternatives.
create table exercise_muscles (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  exercise_id uuid not null references exercises (id),
  muscle_id uuid not null references muscles (id),
  role text not null
);
create unique index uq_exercise_muscles_alive on exercise_muscles (exercise_id, muscle_id) where deleted_at is null;
create index idx_exercise_muscles_muscle_id on exercise_muscles (muscle_id);
select pfs_attach('exercise_muscles', 'editable');

-- Links only. Ranking suggestions is Stage 4.
create table exercise_alternatives (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  exercise_id uuid not null references exercises (id),
  alternative_id uuid not null references exercises (id),
  note text,
  constraint ck_exercise_alternatives_different check (exercise_id <> alternative_id)
);
create unique index uq_exercise_alternatives_alive on exercise_alternatives (exercise_id, alternative_id) where deleted_at is null;
select pfs_attach('exercise_alternatives', 'editable');
