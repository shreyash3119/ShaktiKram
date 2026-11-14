-- Stage 5: the reporting role can read everything and write nothing.
begin;
do $$ begin
  assert not has_function_privilege('pfs_reader', 'api_apply_operations(uuid,uuid,jsonb)', 'execute'), 'reader cannot call the write API';
  assert not has_function_privilege('pfs_reader', 'pfs_restore_finish()', 'execute');
  assert (select rolconfig from pg_roles where rolname = 'pfs_reader') @> array['default_transaction_read_only=on'], 'reader sessions are read-only';
end $$;
set local role pfs_reader;
do $$ declare t text; n integer := 0; begin
  assert (select count(*) from muscles) = 29 and (select count(*) from app_owner) >= 0, 'reader sees rows through row level security';
  assert (select count(*) from v_session_summary) >= 0 and (select count(*) from v_goal_progress) >= 0, 'reader can use the views';
  assert (select count(*) from pfs_table_fingerprints()) > 40, 'reader can fingerprint every table';
  for t in select c.relname from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' loop
    perform t_expect_error(format('delete from %I', t), 'permission denied');
    n := n + 1;
  end loop;
  assert n > 40, 'every table refuses deletes';
  perform t_expect_error($q$insert into goals (type, title) values ('strength', 'x')$q$, 'permission denied');
  perform t_expect_error($q$update settings set time_zone = 'UTC'$q$, 'permission denied');
  perform t_expect_error($q$select api_apply_operations(gen_random_uuid(), gen_random_uuid(), '[]')$q$, 'permission denied');
end $$;
rollback;
