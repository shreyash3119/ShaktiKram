-- Stage 2 / workout sessions, session exercises and sets.
-- A session stores the split and template versions that applied; each session exercise keeps a snapshot of its prescription.

create table workout_sessions (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  occurred_at timestamptz not null,                 -- start of the workout
  ended_at timestamptz,
  local_date date not null, tz_offset_minutes smallint not null,
  name text, status text not null default 'in_progress',
  schedule_entry_id uuid references schedule_entries (id),
  split_version_id uuid references split_versions (id),
  split_day_id uuid references split_days (id),
  template_version_id uuid references template_versions (id),
  paused_seconds integer not null default 0,
  notes text, post_notes text,
  constraint ck_workout_sessions_paused_nonnegative check (paused_seconds >= 0),
  constraint ck_workout_sessions_end_after_start check (ended_at is null or ended_at >= occurred_at),
  constraint ck_workout_sessions_completed_has_end check (status <> 'completed' or ended_at is not null)
);
create index idx_workout_sessions_local_date on workout_sessions (local_date);
create index idx_workout_sessions_template_version_id on workout_sessions (template_version_id);
create index idx_workout_sessions_split_version_id on workout_sessions (split_version_id);
select pfs_attach('workout_sessions', 'editable', false, true);

alter table schedule_entries add constraint fk_schedule_entries_session_id foreign key (session_id) references workout_sessions (id);

create table session_exercises (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  session_id uuid not null references workout_sessions (id),
  exercise_id uuid not null references exercises (id),
  position integer not null,
  status text not null default 'done', skip_reason text,
  substituted_for_exercise_id uuid references exercises (id),
  template_exercise_id uuid references template_exercises (id),
  prescription_snapshot jsonb, notes text,
  constraint ck_session_exercises_position_positive check (position >= 1)
);
create unique index uq_session_exercises_position on session_exercises (session_id, position) where deleted_at is null;
create index idx_session_exercises_exercise_id on session_exercises (exercise_id);
select pfs_attach('session_exercises', 'editable');

-- Copies the prescription when a session exercise is created from a template row. Once set, the snapshot never changes.
create function pfs_session_exercise_snapshot() returns trigger language plpgsql as $$
declare te template_exercises%rowtype; ex text;
begin
  if pfs_restore_allowed() then return new; end if;
  if tg_op = 'UPDATE' then
    if old.prescription_snapshot is not null and new.prescription_snapshot is distinct from old.prescription_snapshot then
      raise exception 'immutable_record: the prescription snapshot of a session exercise cannot change';
    end if;
    return new;
  end if;
  if new.prescription_snapshot is null and new.template_exercise_id is not null then
    select * into te from template_exercises where id = new.template_exercise_id;
    if found then
      select name into ex from exercises where id = te.exercise_id;
      new.prescription_snapshot := jsonb_build_object('template_version_id', te.template_version_id, 'template_exercise_id', te.id,
        'exercise_id', te.exercise_id, 'exercise_name', ex, 'target_sets', te.target_sets, 'rep_min', te.rep_min, 'rep_max', te.rep_max,
        'start_weight_kg', te.start_weight_kg, 'rest_s', te.rest_s, 'rir_target', te.rir_target, 'rpe_target', te.rpe_target,
        'warmup_guidance', te.warmup_guidance, 'notes', te.notes);
    end if;
  end if;
  return new;
end $$;
create trigger d_pfs_session_exercise_snapshot before insert or update on session_exercises
  for each row execute function pfs_session_exercise_snapshot();

create table sets (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  session_exercise_id uuid not null references session_exercises (id),
  set_number smallint not null, set_type text not null default 'working',
  weight_kg numeric(6,2), reps smallint, completed boolean not null default true,
  rir smallint, rpe numeric(3,1), rest_s integer, notes text,
  occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null,
  constraint ck_sets_set_number_positive check (set_number >= 1),
  constraint ck_sets_weight_nonnegative check (weight_kg is null or weight_kg >= 0),
  constraint ck_sets_reps_nonnegative check (reps is null or reps >= 0),
  constraint ck_sets_rir check (rir is null or rir between 0 and 10),
  constraint ck_sets_rpe check (rpe is null or (rpe between 1 and 10 and rpe * 2 = round(rpe * 2))),
  constraint ck_sets_rest_nonnegative check (rest_s is null or rest_s >= 0)
);
create unique index uq_sets_number on sets (session_exercise_id, set_type, set_number) where deleted_at is null;
create index idx_sets_local_date on sets (local_date);
select pfs_attach('sets', 'append_only', false, true);
