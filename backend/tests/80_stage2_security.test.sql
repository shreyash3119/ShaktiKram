-- Stage 2 security: extension out of the public schema, views respect row level security, no direct writes.
begin;
do $$ begin
  assert (select n.nspname from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'btree_gist') = 'extensions', 'btree_gist lives outside the public schema';
  assert not has_function_privilege('authenticated', 'pfs_split_single_active()', 'execute');
  assert has_function_privilege('authenticated', 'api_compare_template_versions(uuid,uuid)', 'execute');
  assert not has_function_privilege('anon', 'api_compare_template_versions(uuid,uuid)', 'execute');
  insert into schedule_entries (local_date, status) values ('2026-10-05', 'planned');
  insert into planned_breaks (title, start_date, end_date) values ('Exam week', '2026-10-05', '2026-10-06');
end $$;

set local role anon;
do $$ declare t text; begin
  for t in select c.relname from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v') loop
    perform t_expect_error(format('select count(*) from %I', t), 'permission denied');
  end loop;
end $$;
reset role;

select set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-0000-0000-00000000000b', true);
set local role authenticated;
do $$ begin
  assert (select count(*) from v_attendance_daily) = 0 and (select count(*) from v_consistency_weekly) = 0
     and (select count(*) from schedule_entries) = 0 and (select count(*) from planned_breaks) = 0, 'non-owner sees no rows through tables or views';
  assert not pfs_is_break_day('2026-10-05'), 'non-owner sees no breaks';
  perform t_expect_error('select api_compare_template_versions(gen_random_uuid(), gen_random_uuid())', 'unauthorized');
end $$;
reset role;

select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-00000000000a', true);
set local role authenticated;
select api_claim_owner();
do $$ begin
  assert (select count(*) from v_attendance_daily) = 1 and pfs_is_break_day('2026-10-05'), 'owner sees the rows';
  perform t_expect_error('insert into sets (session_exercise_id, set_number, occurred_at, local_date, tz_offset_minutes) values (gen_random_uuid(), 1, now(), current_date, 0)', 'permission denied');
  perform t_expect_error('update schedule_entries set status = ''skipped''', 'permission denied');
  perform t_expect_error('delete from workout_sessions', 'permission denied');
end $$;
rollback;
