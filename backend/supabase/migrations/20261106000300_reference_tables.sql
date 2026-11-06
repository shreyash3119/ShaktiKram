-- Stage 1 / reference tables. Seeded rows (is_custom = false) are protected from client changes.
-- Rows created through the API are always custom.

create function pfs_reference_guard() returns trigger language plpgsql as $$
declare
  v_allowed text[] := coalesce(string_to_array(nullif(tg_argv[0], ''), ','), '{}');
  v_skip text[] := array['rev', 'updated_at', 'device_id'];
begin
  if not pfs_flag('pfs.in_api') then return new; end if;
  if tg_op = 'INSERT' then new.is_custom := true; return new; end if;
  if old.is_custom then return new; end if;
  if (to_jsonb(new) - v_allowed - v_skip) is distinct from (to_jsonb(old) - v_allowed - v_skip) then
    raise exception 'immutable_record: seeded reference rows cannot be changed';
  end if;
  return new;
end $$;

create table muscles (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  key text not null, group_key text not null, label text not null, is_custom boolean not null default false,
  constraint uq_muscles_key unique (key),
  constraint ck_muscles_key_format check (key ~ '^[a-z][a-z0-9]*(_[a-z0-9]+)*$'),
  constraint ck_muscles_group_key_format check (group_key ~ '^[a-z][a-z0-9]*(_[a-z0-9]+)*$')
);
select pfs_attach('muscles', 'editable');
create trigger d_pfs_reference_guard before insert or update on muscles for each row execute function pfs_reference_guard('');

create table body_regions (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  key text not null, label text not null, is_custom boolean not null default false,
  constraint uq_body_regions_key unique (key),
  constraint ck_body_regions_key_format check (key ~ '^[a-z][a-z0-9]*(_[a-z0-9]+)*$')
);
select pfs_attach('body_regions', 'editable');
create trigger d_pfs_reference_guard before insert or update on body_regions for each row execute function pfs_reference_guard('');

-- Equipment: the list is seeded, but the user marks what their gym has.
create table equipment (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  key text not null, label text not null, is_available_at_gym boolean not null default true,
  is_custom boolean not null default false,
  constraint uq_equipment_key unique (key),
  constraint ck_equipment_key_format check (key ~ '^[a-z][a-z0-9]*(_[a-z0-9]+)*$')
);
select pfs_attach('equipment', 'editable');
create trigger d_pfs_reference_guard before insert or update on equipment for each row execute function pfs_reference_guard('is_available_at_gym');

-- Stub so later tables (restrictions, template exercises, sets) can reference exercises before Stage 2 defines it fully.
-- Stage 2 extends this table with a new migration.
create table exercises (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  name text not null, is_custom boolean not null default true,
  constraint ck_exercises_name_not_blank check (length(trim(name)) > 0)
);
select pfs_attach('exercises', 'editable');
