-- Stage 3 / supplements (feature 8). Records what the user enters. The app never tells the user to start, stop or change one.

create table supplements (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  name text not null, category text, label_info text, observations text,
  cost_amount numeric(10,2), cost_currency text, notes text,
  constraint ck_supplements_name_not_blank check (length(trim(name)) > 0),
  constraint ck_supplements_cost_nonnegative check (cost_amount is null or cost_amount >= 0)
);
create unique index uq_supplements_name_alive on supplements (lower(name)) where deleted_at is null;
select pfs_attach('supplements', 'editable', true);

-- One version per phase: start, pause, restart and stop each open a new version (status + dose + reason in change_reason).
create table supplement_phases (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  entity_id uuid not null references supplements (id), version integer not null,
  effective_from timestamptz not null, effective_to timestamptz,
  previous_version_id uuid references supplement_phases (id), change_reason text,
  status text not null default 'active',
  dose_amount numeric(10,3), dose_unit text, times_per_day smallint not null default 1,
  days_of_week smallint[] not null default '{}',            -- ISO weekdays; empty means every day
  planned_duration_days integer, max_daily_dose numeric(10,3), notes text,
  constraint ck_supplement_phases_version_positive check (version >= 1),
  constraint ck_supplement_phases_interval check (effective_to is null or effective_to >= effective_from),
  constraint ck_supplement_phases_dose_positive check (dose_amount is null or dose_amount > 0),
  constraint ck_supplement_phases_times_positive check (times_per_day >= 1),
  constraint ck_supplement_phases_days check (days_of_week <@ array[1,2,3,4,5,6,7]::smallint[]),
  constraint ck_supplement_phases_duration_positive check (planned_duration_days is null or planned_duration_days > 0),
  constraint ck_supplement_phases_limit_positive check (max_daily_dose is null or max_daily_dose > 0),
  constraint uq_supplement_phases_entity_id_version unique (entity_id, version),
  constraint ex_supplement_phases_no_overlap exclude using gist (entity_id with =, tstzrange(effective_from, effective_to, '[)') with &&)
);
create unique index uq_supplement_phases_one_current on supplement_phases (entity_id) where effective_to is null and deleted_at is null;
select pfs_attach('supplement_phases', 'versioned', true);

create table supplement_logs (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  supplement_id uuid not null references supplements (id),
  phase_id uuid references supplement_phases (id),
  outcome text not null, quantity numeric(10,3), unit text, notes text,
  occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null,
  constraint ck_supplement_logs_quantity_nonnegative check (quantity is null or quantity >= 0)
);
create index idx_supplement_logs_supplement_id on supplement_logs (supplement_id, local_date);
create index idx_supplement_logs_phase_id on supplement_logs (phase_id);
select pfs_attach('supplement_logs', 'append_only', false, true);
