-- Common columns, soft delete, audit, event dates, goal status history.
begin;
do $$
declare a uuid; b uuid; g goals%rowtype; r1 bigint; u1 timestamptz; n integer; au audit_log%rowtype;
  gid constant uuid := '018f0000-0000-7000-8000-000000000001';
begin
  -- uuid_v7
  a := uuid_v7(); perform pg_sleep(0.01); b := uuid_v7();
  assert substr(a::text, 15, 1) = '7', 'uuid_v7 version nibble is 7';
  assert substr(a::text, 20, 1) in ('8', '9', 'a', 'b'), 'uuid_v7 variant bits';
  assert a < b, 'uuid_v7 sorts by creation time';

  -- bookkeeping columns cannot be forced by the writer
  insert into goals (id, type, title, rev, created_at) values (gid, 'strength', 'Bench 80', 999999999, '2000-01-01') returning * into g;
  assert g.rev <> 999999999 and g.created_at > '2000-01-01', 'rev and created_at are set by the database';
  r1 := g.rev; u1 := g.updated_at; perform pg_sleep(0.01);
  update goals set title = 'Bench 85' where id = gid returning * into g;
  assert g.rev > r1, 'rev increases on update';
  assert g.created_at > '2000-01-01', 'created_at kept';

  -- hard delete blocked, soft delete allowed
  perform t_expect_error(format('delete from goals where id = %L', gid), 'immutable_record');
  update goals set deleted_at = now() where id = gid;
  assert (select deleted_at from goals where id = gid) is not null;

  -- audit: insert logged for goals, update/delete log only changed columns
  select count(*) into n from audit_log where record_id = gid and action = 'insert';
  assert n = 1, 'goal insert audited';
  select * into au from audit_log where record_id = gid and action = 'update';
  assert au.before = '{"title": "Bench 80"}'::jsonb and au.after = '{"title": "Bench 85"}'::jsonb, 'update audit holds only changed columns';
  assert exists (select 1 from audit_log where record_id = gid and action = 'delete'), 'soft delete audited as delete';
  insert into exercises (id, name) values ('018f0000-0000-7000-8000-000000000002', 'Test curl');
  assert not exists (select 1 from audit_log where record_id = '018f0000-0000-7000-8000-000000000002'), 'inserts audited for plan and goal tables only';

  -- audit_log is append-only
  perform t_expect_error('update audit_log set reason = ''x''', 'immutable_record');
  perform t_expect_error('delete from audit_log', 'immutable_record');
  perform t_expect_error('truncate audit_log', 'immutable_record');
end $$;

-- event tables: local_date must match occurred_at shifted by tz offset
create temp table ev (id uuid primary key default uuid_v7(), occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null);
create trigger t_local before insert or update on ev for each row execute function pfs_check_local_date();
do $$ begin
  insert into ev (occurred_at, local_date, tz_offset_minutes) values ('2026-11-05T20:00:00Z', '2026-11-06', 330);
  perform t_expect_error('insert into ev (occurred_at, local_date, tz_offset_minutes) values (''2026-11-05T20:00:00Z'', ''2026-11-05'', 330)', 'validation_failed');
end $$;

-- goal status history is written by a trigger (time zone from settings: Asia/Kolkata, +330 min)
do $$
declare gid uuid := '018f0000-0000-7000-8000-000000000003'; e goal_status_events%rowtype;
begin
  insert into goals (id, type, title) values (gid, 'cutting', 'Cut');
  update goals set status = 'paused' where id = gid;
  assert (select count(*) from goal_status_events where goal_id = gid) = 2, 'initial status and change both recorded';
  select * into e from goal_status_events where goal_id = gid and status = 'paused';
  assert e.tz_offset_minutes = 330, 'offset from settings time zone';
  assert e.local_date = ((e.occurred_at at time zone 'UTC') + interval '330 minutes')::date, 'local_date matches';
  perform t_expect_error('update settings set time_zone = ''Mars/Olympus''', 'validation_failed');
end $$;
rollback;
