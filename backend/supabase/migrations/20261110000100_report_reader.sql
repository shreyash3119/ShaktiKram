-- Stage 5 / read-only role for the reporting service (FastAPI). It can read everything and write nothing (decision D18).
-- Give it a password outside the migrations: alter role pfs_reader login password '...';

do $$
begin
  if not exists (select from pg_roles where rolname = 'pfs_reader') then create role pfs_reader nologin; end if;
end $$;
alter role pfs_reader set default_transaction_read_only = on;
grant usage on schema public to pfs_reader;

-- New tables are secured through pfs_secure; it now also lets the reader read them.
create or replace function pfs_secure(p_table regclass) returns void language plpgsql as $$
begin
  execute format('alter table %s enable row level security', p_table);
  execute format('drop policy if exists owner_select on %s', p_table);
  execute format('create policy owner_select on %s for select to authenticated using (is_owner())', p_table);
  execute format('revoke all on %s from anon, authenticated', p_table);
  execute format('grant select on %s to authenticated', p_table);
  if exists (select from pg_roles where rolname = 'pfs_reader') then
    execute format('drop policy if exists reader_select on %s', p_table);
    execute format('create policy reader_select on %s for select to pfs_reader using (true)', p_table);
    execute format('grant select on %s to pfs_reader', p_table);
  end if;
end $$;

-- Call this at the end of any migration that adds a view: views are not covered by pfs_secure.
create function pfs_grant_reader() returns void language plpgsql as $$
declare r record;
begin
  for r in select c.relname, c.relkind, c.relrowsecurity from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v') loop
    execute format('grant select on %I to pfs_reader', r.relname);
    if r.relkind = 'r' and r.relrowsecurity then
      execute format('drop policy if exists reader_select on %I', r.relname);
      execute format('create policy reader_select on %I for select to pfs_reader using (true)', r.relname);
    end if;
  end loop;
end $$;
select pfs_grant_reader();

-- Views run as the caller, so the functions they use must be callable by the reader too.
grant execute on function pfs_table_fingerprints(), pfs_tz(), pfs_local_date(timestamptz), pfs_local_today(), pfs_is_break_day(date),
  pfs_muscle_category(integer), pfs_target_on(date), pfs_e1rm(numeric, integer), calc_trend(jsonb), calc_goal_progress(jsonb), pfs_goal_values(uuid) to pfs_reader;
