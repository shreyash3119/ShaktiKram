-- Stage 2 / schedule, gym decisions, planned breaks.

create table schedule_entries (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  local_date date not null,
  is_rest_day boolean not null default false,
  split_version_id uuid references split_versions (id),
  split_day_id uuid references split_days (id),
  template_version_id uuid references template_versions (id),
  status text not null default 'planned',
  session_id uuid,                                  -- foreign key added with workout_sessions
  rescheduled_to date, replaced_by_activity text, reason text, notes text,
  constraint ck_schedule_entries_completed_has_session check (status <> 'completed' or session_id is not null),
  constraint ck_schedule_entries_rescheduled_has_date check (status <> 'rescheduled' or (rescheduled_to is not null and rescheduled_to <> local_date)),
  constraint ck_schedule_entries_replaced_has_activity check (status <> 'replaced' or replaced_by_activity is not null)
);
create unique index uq_schedule_entries_local_date on schedule_entries (local_date) where deleted_at is null;
select pfs_attach('schedule_entries', 'editable');

-- The user's answer to "Should I go to the gym today?" (context holds what was shown; never a medical decision).
create table gym_decisions (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null,
  outcome text not null,
  schedule_entry_id uuid references schedule_entries (id),
  context jsonb not null default '{}'::jsonb, notes text
);
create index idx_gym_decisions_local_date on gym_decisions (local_date);
select pfs_attach('gym_decisions', 'append_only', false, true);

create table planned_breaks (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  title text not null, start_date date not null, end_date date not null,
  reason text not null default 'other', mode text not null default 'full',
  notes text, status text not null default 'planned', planned_return_date date,
  constraint ck_planned_breaks_title_not_blank check (length(trim(title)) > 0),
  constraint ck_planned_breaks_dates check (end_date >= start_date),
  constraint ck_planned_breaks_return check (planned_return_date is null or planned_return_date > end_date)
);
create index idx_planned_breaks_dates on planned_breaks (start_date, end_date);
select pfs_attach('planned_breaks', 'editable', true);

create table break_events (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  break_id uuid not null references planned_breaks (id),
  event text not null, note text, new_end_date date,
  occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null
);
create index idx_break_events_break_id on break_events (break_id, occurred_at);
select pfs_attach('break_events', 'append_only', false, true);
