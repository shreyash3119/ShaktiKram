-- Stage 1 / security: function privileges, private storage buckets, deny-by-default report.

-- Only the api_* functions and is_owner() are callable by signed-in users. Everything else is internal.
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
-- Re-grant read access (RLS still limits it to the owner) on every table the owner may read.
do $$
declare r record;
begin
  for r in select table_name as n from pfs_registry union select unnest(array['pfs_registry', 'audit_log', 'devices', 'sync_operations']) loop
    execute format('grant select on %I to authenticated', r.n);
  end loop;
end $$;
grant execute on function is_owner(), api_claim_owner(), api_register_device(uuid, text, text), api_list_devices(),
  api_revoke_device(uuid), api_apply_operations(uuid, uuid, jsonb), api_pull_changes(uuid, bigint, integer) to authenticated;

-- Tables that are not RLS-protected (should always be empty).
create function pfs_unprotected_tables() returns setof text language sql stable as $$
  select c.relname::text from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and not c.relrowsecurity
$$;

-- Private storage buckets. Files are reached only with short-lived signed URLs (created with the owner's session).
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public) values ('media', 'media', false), ('backups', 'backups', false)
    on conflict (id) do update set public = false;
    drop policy if exists pfs_media_owner on storage.objects;
    drop policy if exists pfs_backups_owner_read on storage.objects;
    create policy pfs_media_owner on storage.objects for all to authenticated
      using (bucket_id = 'media' and is_owner()) with check (bucket_id = 'media' and is_owner());
    create policy pfs_backups_owner_read on storage.objects for select to authenticated
      using (bucket_id = 'backups' and is_owner());
  end if;
end $$;
