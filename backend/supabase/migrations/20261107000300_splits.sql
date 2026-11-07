-- Stage 2 / workout splits. Identity (with status) + immutable versions + days. One split is active at a time.

create table splits (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  status text not null default 'draft'
);
create unique index uq_splits_one_active on splits ((true)) where status = 'active' and deleted_at is null;
select pfs_attach('splits', 'editable', true);

-- Activating a split deactivates the one that was active (each change is audited and recorded in the status timeline).
create function pfs_split_single_active() returns trigger language plpgsql as $$
begin
  if pfs_restore_allowed() then return new; end if;
  update splits set status = 'inactive' where status = 'active' and deleted_at is null and id <> new.id;
  return new;
end $$;
create trigger c_pfs_split_single_active before insert or update of status on splits
  for each row when (new.status = 'active') execute function pfs_split_single_active();

create table split_versions (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  entity_id uuid not null references splits (id), version integer not null,
  effective_from timestamptz not null, effective_to timestamptz,
  previous_version_id uuid references split_versions (id), change_reason text,
  name text not null, pattern text not null default 'fixed_weekly', cycle_length_days smallint, notes text,
  constraint ck_split_versions_version_positive check (version >= 1),
  constraint ck_split_versions_interval check (effective_to is null or effective_to >= effective_from),
  constraint ck_split_versions_name_not_blank check (length(trim(name)) > 0),
  constraint ck_split_versions_cycle_positive check (cycle_length_days is null or cycle_length_days >= 1),
  constraint uq_split_versions_entity_id_version unique (entity_id, version),
  constraint ex_split_versions_no_overlap exclude using gist (entity_id with =, tstzrange(effective_from, effective_to, '[)') with &&)
);
create unique index uq_split_versions_one_current on split_versions (entity_id) where effective_to is null and deleted_at is null;
select pfs_attach('split_versions', 'versioned', true);

create table split_days (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  split_version_id uuid not null references split_versions (id),
  position smallint not null, label text not null, is_rest boolean not null default false,
  template_id uuid references workout_templates (id),
  constraint ck_split_days_position_positive check (position >= 1),
  constraint ck_split_days_rest_has_no_template check (not (is_rest and template_id is not null)),
  constraint uq_split_days_id_split_version_id unique (id, split_version_id)
);
create unique index uq_split_days_position on split_days (split_version_id, position) where deleted_at is null;
create index idx_split_days_template_id on split_days (template_id);
select pfs_attach('split_days', 'editable');
create trigger e_pfs_version_child_guard before insert or update on split_days
  for each row execute function pfs_version_child_guard('split_versions', 'split_version_id', 'workout_sessions:split_version_id,schedule_entries:split_version_id');

create table split_day_muscles (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  split_day_id uuid not null, split_version_id uuid not null,
  muscle_id uuid not null references muscles (id),
  constraint fk_split_day_muscles_split_day_id foreign key (split_day_id, split_version_id) references split_days (id, split_version_id)
);
create unique index uq_split_day_muscles_alive on split_day_muscles (split_day_id, muscle_id) where deleted_at is null;
select pfs_attach('split_day_muscles', 'editable');
create trigger e_pfs_version_child_guard before insert or update on split_day_muscles
  for each row execute function pfs_version_child_guard('split_versions', 'split_version_id', 'workout_sessions:split_version_id,schedule_entries:split_version_id');

-- Status timeline of each split (activation periods). Written by a trigger so a client cannot skip it.
create table split_status_events (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  split_id uuid not null references splits (id),
  status text not null, reason text,
  occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null
);
create index idx_split_status_events_split_id on split_status_events (split_id, occurred_at);
select pfs_attach('split_status_events', 'append_only', false, true, false);

create function pfs_split_status_event() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare tz text; off integer; t timestamptz := now();
begin
  if pfs_restore_allowed() then return null; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then return null; end if;
  select time_zone into tz from settings limit 1;
  tz := coalesce(tz, 'UTC');
  off := (extract(epoch from ((t at time zone tz) - (t at time zone 'UTC'))) / 60)::integer;
  insert into split_status_events (split_id, status, reason, occurred_at, local_date, tz_offset_minutes)
  values (new.id, new.status, nullif(current_setting('pfs.reason', true), ''), t,
          ((t at time zone 'UTC') + make_interval(mins => off))::date, off);
  return null;
end $$;
create trigger y_split_status_event after insert or update on splits for each row execute function pfs_split_status_event();
