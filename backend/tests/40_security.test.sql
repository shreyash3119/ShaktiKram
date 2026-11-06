-- Private access: RLS everywhere, anon blocked, non-owner blocked, no direct writes, private storage.
begin;
do $$ declare r text; begin
  for r in select * from pfs_unprotected_tables() loop raise exception 'table without row level security: %', r; end loop;
  assert not has_function_privilege('anon', 'api_apply_operations(uuid,uuid,jsonb)', 'execute'), 'anon cannot call the write API';
  assert has_function_privilege('authenticated', 'api_apply_operations(uuid,uuid,jsonb)', 'execute');
  assert not has_function_privilege('authenticated', 'pfs_new_version(text,jsonb,text)', 'execute'), 'internal functions are not callable';
  assert not has_function_privilege('authenticated', 'pfs_restore_finish()', 'execute');
  assert not exists (select 1 from storage.buckets where public), 'all buckets private';
end $$;

-- the seed leaves rows in the database; the owner is not claimed yet
set local role anon;
do $$ declare t text; begin
  for t in select c.relname from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' loop
    perform t_expect_error(format('select count(*) from %I', t), 'permission denied');
  end loop;
  perform t_expect_error('select api_claim_owner()', 'permission denied');
  perform t_expect_error('select is_owner()', 'permission denied');
end $$;
reset role;

-- a signed-in user who is not the owner sees nothing
select set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-0000-0000-00000000000b', true);
set local role authenticated;
do $$ begin
  assert (select count(*) from goals) = 0 and (select count(*) from muscles) = 0 and (select count(*) from audit_log) = 0, 'non-owner sees no rows';
  perform t_expect_error('select count(*) from app_owner', 'permission denied');
  perform t_expect_error('insert into storage.objects (bucket_id, name) values (''media'', ''x.jpg'')', 'row-level security');
end $$;
reset role;

-- the owner can read but not write directly
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-00000000000a', true);
set local role authenticated;
select api_claim_owner();
do $$ begin
  assert (select count(*) from muscles) = 29 and (select count(*) from goals) >= 2, 'owner reads';
  perform t_expect_error('insert into goals (type, title) values (''strength'', ''direct'')', 'permission denied');
  perform t_expect_error('update goals set title = ''x''', 'permission denied');
  perform t_expect_error('delete from goals', 'permission denied');
  perform t_expect_error('insert into audit_log (table_name, record_id, action, rev) values (''x'', gen_random_uuid(), ''update'', 1)', 'permission denied');
  perform t_expect_error('insert into app_owner (auth_user_id) values (gen_random_uuid())', 'permission denied');
  insert into storage.objects (bucket_id, name) values ('media', 'abc123.jpg');
  perform t_expect_error('insert into storage.objects (bucket_id, name) values (''backups'', ''x.dump'')', 'row-level security');
  perform t_expect_error('insert into storage.objects (bucket_id, name) values (''other'', ''x'')', 'violates');
end $$;
rollback;
