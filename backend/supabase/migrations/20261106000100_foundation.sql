-- Stage 1 / foundation: extensions, global revision sequence, uuid_v7, owner check, table registry,
-- common-column triggers, audit log, versioning guard, restore mode. Conventions: docs/TECHNICAL_CONTRACT.md

create extension if not exists btree_gist;

-- Default-deny for the public API roles on everything created from now on (RLS and grants below).
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public;

create sequence pfs_global_rev;

-- UUIDv7: 48-bit millisecond timestamp, then random bits, so ids sort by creation time.
create function uuid_v7() returns uuid language sql volatile as $$
  select encode(set_bit(set_bit(overlay(uuid_send(gen_random_uuid())
    placing substring(int8send((extract(epoch from clock_timestamp()) * 1000)::bigint) from 3) from 1 for 6), 52, 1), 53, 1), 'hex')::uuid
$$;

-- Single owner (decision D3). Filled once by api_claim_owner().
create table app_owner (
  singleton boolean primary key default true check (singleton),
  auth_user_id uuid not null unique,
  claimed_at timestamptz not null default now()
);
alter table app_owner enable row level security;  -- no policies: no client access at all

create function is_owner() returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from app_owner where auth_user_id = auth.uid())
$$;

create function pfs_meta(p_request_id uuid default null, p_next_cursor text default null) returns jsonb language sql stable as $$
  select jsonb_build_object('request_id', p_request_id, 'server_time', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                            'schema_version', 1, 'next_cursor', p_next_cursor)
$$;

create function pfs_flag(p text) returns boolean language sql stable as $$
  select coalesce(current_setting(p, true), '') = 'on'
$$;
-- Restore mode keeps ids, revs and timestamps as supplied. Only server-side roles may use it.
create function pfs_restore_allowed() returns boolean language sql stable as $$
  select pfs_flag('pfs.restore_mode') and current_user not in ('anon', 'authenticated')
$$;

-- Registry of synced tables. pfs_attach() fills it. api_pull_changes and backups read it.
create table pfs_registry (
  table_name text primary key,
  record_class text not null,
  audit_inserts boolean not null default false,
  client_writable boolean not null default true
);

-- Row Level Security: enabled on every table; only the owner may read; nobody may write directly.
create function pfs_secure(p_table regclass) returns void language plpgsql as $$
begin
  execute format('alter table %s enable row level security', p_table);
  execute format('drop policy if exists owner_select on %s', p_table);
  execute format('create policy owner_select on %s for select to authenticated using (is_owner())', p_table);
  execute format('revoke all on %s from anon, authenticated', p_table);
  execute format('grant select on %s to authenticated', p_table);
end $$;
select pfs_secure('pfs_registry');

-- BEFORE INSERT/UPDATE: bookkeeping the client can never set.
create function pfs_before_write() returns trigger language plpgsql as $$
declare v_dev uuid := nullif(current_setting('pfs.device_id', true), '')::uuid;
begin
  if pfs_restore_allowed() then return new; end if;
  if tg_op = 'INSERT' then
    new.id := coalesce(new.id, uuid_v7());
    new.created_at := now();
  else
    new.id := old.id;
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  new.rev := nextval('pfs_global_rev');
  if v_dev is not null then new.device_id := v_dev; end if;
  return new;
end $$;

create function pfs_block_delete() returns trigger language plpgsql as $$
begin
  if pfs_flag('pfs.allow_purge') and current_user not in ('anon', 'authenticated') then return old; end if;
  raise exception 'immutable_record: hard delete is blocked on %; use soft delete', tg_table_name;
end $$;

create table audit_log (
  id uuid primary key default uuid_v7(),
  table_name text not null,
  record_id uuid not null,
  action text not null,
  before jsonb,
  after jsonb,
  reason text,
  device_id uuid,
  at timestamptz not null default now(),
  rev bigint not null
);
create index idx_audit_log_table_name_record_id on audit_log (table_name, record_id, at);
select pfs_secure('audit_log');

create function pfs_audit_immutable() returns trigger language plpgsql as $$
begin raise exception 'immutable_record: audit_log is append-only'; end $$;
create trigger a_audit_log_no_change before update or delete on audit_log for each row execute function pfs_audit_immutable();
create trigger b_audit_log_no_truncate before truncate on audit_log for each statement execute function pfs_audit_immutable();

-- AFTER INSERT/UPDATE: audit. Updates store only the changed columns (before and after).
create function pfs_audit() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_reg pfs_registry%rowtype; v_old jsonb; v_new jsonb := to_jsonb(new);
  v_before jsonb; v_after jsonb; v_action text;
  v_reason text := nullif(current_setting('pfs.reason', true), '');
  v_dev uuid := nullif(current_setting('pfs.device_id', true), '')::uuid;
begin
  if pfs_restore_allowed() then return null; end if;
  select * into v_reg from pfs_registry where table_name = tg_table_name;
  if tg_op = 'INSERT' then
    if v_reg.audit_inserts then
      insert into audit_log (table_name, record_id, action, before, after, reason, device_id, rev)
      values (tg_table_name, new.id, 'insert', null, v_new, v_reason, v_dev, new.rev);
    end if;
    return null;
  end if;
  v_old := to_jsonb(old);
  select coalesce(jsonb_object_agg(n.key, n.value), '{}'::jsonb), coalesce(jsonb_object_agg(n.key, v_old -> n.key), '{}'::jsonb)
    into v_after, v_before
    from jsonb_each(v_new) n
   where n.key not in ('rev', 'updated_at', 'device_id') and n.value is distinct from v_old -> n.key;
  if v_after = '{}'::jsonb then return null; end if;
  v_action := case
    when old.deleted_at is null and new.deleted_at is not null then 'delete'
    when old.deleted_at is not null and new.deleted_at is null then 'restore'
    when v_after ? 'effective_to' and (select count(*) from jsonb_object_keys(v_after)) = 1 then 'version_close'
    else 'update' end;
  insert into audit_log (table_name, record_id, action, before, after, reason, device_id, rev)
  values (tg_table_name, new.id, v_action, v_before, v_after, v_reason, v_dev, new.rev);
  return null;
end $$;

-- Versioned rows are immutable except for closing effective_to once (and bookkeeping columns).
create function pfs_versioned_guard() returns trigger language plpgsql as $$
begin
  if pfs_restore_allowed() then return new; end if;
  if (to_jsonb(new) - array['effective_to', 'rev', 'updated_at', 'device_id', 'deleted_at'])
     is distinct from (to_jsonb(old) - array['effective_to', 'rev', 'updated_at', 'device_id', 'deleted_at']) then
    raise exception 'immutable_record: version rows cannot be edited; create a new version';
  end if;
  if new.effective_to is distinct from old.effective_to then
    if old.effective_to is not null then raise exception 'immutable_record: this version is already closed'; end if;
    if new.effective_to < new.effective_from then raise exception 'version_conflict: effective_to is before effective_from'; end if;
  end if;
  return new;
end $$;

-- Event tables: local_date must match occurred_at shifted by tz_offset_minutes.
create function pfs_check_local_date() returns trigger language plpgsql as $$
begin
  if new.local_date is distinct from ((new.occurred_at at time zone 'UTC') + make_interval(mins => new.tz_offset_minutes))::date then
    raise exception 'validation_failed: local_date does not match occurred_at shifted by tz_offset_minutes';
  end if;
  return new;
end $$;

-- Attach the common behaviour to a table. Tables must already have the common columns:
-- id, created_at, updated_at, deleted_at, rev, device_id.
create function pfs_attach(p_table regclass, p_class text, p_audit_inserts boolean default false,
                           p_event boolean default false, p_client_writable boolean default true) returns void
language plpgsql as $$
begin
  insert into pfs_registry (table_name, record_class, audit_inserts, client_writable)
  values (p_table::text, p_class, p_audit_inserts, p_client_writable)
  on conflict (table_name) do update set record_class = excluded.record_class, audit_inserts = excluded.audit_inserts,
    client_writable = excluded.client_writable;
  execute format('create trigger a_pfs_before_write before insert or update on %s for each row execute function pfs_before_write()', p_table);
  execute format('create trigger b_pfs_block_delete before delete on %s for each row execute function pfs_block_delete()', p_table);
  execute format('create trigger z_pfs_audit after insert or update on %s for each row execute function pfs_audit()', p_table);
  if p_class = 'versioned' then
    execute format('create trigger c_pfs_versioned_guard before update on %s for each row execute function pfs_versioned_guard()', p_table);
  end if;
  if p_event then
    execute format('create trigger c_pfs_local_date before insert or update on %s for each row execute function pfs_check_local_date()', p_table);
  end if;
  perform pfs_secure(p_table);
end $$;

-- Backup and restore support.
create function pfs_restore_finish() returns bigint language plpgsql as $$
declare r record; m bigint := 0; x bigint;
begin
  if current_user in ('anon', 'authenticated') then raise exception 'unauthorized: restore is a server-side operation'; end if;
  for r in select table_name from pfs_registry loop
    execute format('select coalesce(max(rev), 0) from %I', r.table_name) into x;
    m := greatest(m, x);
  end loop;
  perform setval('pfs_global_rev', greatest(m, (select last_value from pfs_global_rev)), true);
  insert into audit_log (table_name, record_id, action, reason, rev) values ('pfs_restore', uuid_v7(), 'restore', 'logical restore finished', m);
  return m;
end $$;

create function pfs_table_fingerprints() returns table (table_name text, row_count bigint, fingerprint text, max_rev bigint)
language plpgsql as $$
declare r record;
begin
  for r in select t.n from (select pr.table_name as n from pfs_registry pr union select 'audit_log') t order by 1 loop
    return query execute format(
      'select %L::text, count(*)::bigint, md5(coalesce(string_agg(to_jsonb(x)::text, %L order by x.id), %L)), coalesce(max(x.rev), 0)::bigint from %I x',
      r.n, ',', '', r.n);
  end loop;
end $$;
