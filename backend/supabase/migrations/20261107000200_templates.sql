-- Stage 2 / workout templates. Identity row + immutable versions + prescription rows that belong to one version.

-- Child rows of a version may change only while the version is open and unused. Afterwards: create a new version.
-- Trigger arguments: parent version table, foreign key column, referencing tables ("table:column,table:column").
create function pfs_version_child_guard() returns trigger language plpgsql as $$
declare
  v_parent text := tg_argv[0]; v_fk text := tg_argv[1]; v_refs text[] := string_to_array(tg_argv[2], ',');
  v_pid uuid := (to_jsonb(new) ->> v_fk)::uuid; v_closed timestamptz; v_used boolean; r text;
begin
  if pfs_restore_allowed() then return new; end if;
  if tg_op = 'UPDATE' and (to_jsonb(old) ->> v_fk)::uuid is distinct from v_pid then
    raise exception 'immutable_record: a row cannot move to another version';
  end if;
  execute format('select effective_to from %I where id = $1', v_parent) into v_closed using v_pid;
  if v_closed is not null then raise exception 'immutable_record: this version is closed; create a new version'; end if;
  foreach r in array v_refs loop
    execute format('select exists (select 1 from %I where %I = $1 and deleted_at is null)', split_part(r, ':', 1), split_part(r, ':', 2)) into v_used using v_pid;
    if v_used then raise exception 'immutable_record: this version is already used by %; create a new version', split_part(r, ':', 1); end if;
  end loop;
  return new;
end $$;

create table workout_templates (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  duplicated_from_id uuid references workout_templates (id)
);
select pfs_attach('workout_templates', 'editable', true);

create table template_versions (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  entity_id uuid not null references workout_templates (id), version integer not null,
  effective_from timestamptz not null, effective_to timestamptz,
  previous_version_id uuid references template_versions (id), change_reason text,
  name text not null, description text,
  constraint ck_template_versions_version_positive check (version >= 1),
  constraint ck_template_versions_interval check (effective_to is null or effective_to >= effective_from),
  constraint ck_template_versions_name_not_blank check (length(trim(name)) > 0),
  constraint uq_template_versions_entity_id_version unique (entity_id, version),
  constraint ex_template_versions_no_overlap exclude using gist (entity_id with =, tstzrange(effective_from, effective_to, '[)') with &&)
);
create unique index uq_template_versions_one_current on template_versions (entity_id) where effective_to is null and deleted_at is null;
select pfs_attach('template_versions', 'versioned', true);

-- The exercise prescription (feature 3): sets, rep range, weight, rest, effort targets, warm-up guidance.
create table template_exercises (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  template_version_id uuid not null references template_versions (id),
  exercise_id uuid not null references exercises (id),
  position integer not null,
  target_sets smallint not null default 3, rep_min smallint, rep_max smallint,
  start_weight_kg numeric(6,2), rest_s integer, rir_target smallint, rpe_target numeric(3,1),
  warmup_guidance text, notes text,
  constraint ck_template_exercises_position_positive check (position >= 1),
  constraint ck_template_exercises_target_sets_positive check (target_sets >= 1),
  constraint ck_template_exercises_rep_range check (rep_min is null or rep_max is null or rep_max >= rep_min),
  constraint ck_template_exercises_rir check (rir_target is null or rir_target between 0 and 10),
  constraint ck_template_exercises_rpe check (rpe_target is null or (rpe_target between 1 and 10 and rpe_target * 2 = round(rpe_target * 2))),
  constraint ck_template_exercises_weight check (start_weight_kg is null or start_weight_kg >= 0)
);
create unique index uq_template_exercises_position on template_exercises (template_version_id, position) where deleted_at is null;
create index idx_template_exercises_exercise_id on template_exercises (exercise_id);
select pfs_attach('template_exercises', 'editable');
create trigger e_pfs_version_child_guard before insert or update on template_exercises
  for each row execute function pfs_version_child_guard('template_versions', 'template_version_id', 'workout_sessions:template_version_id');
