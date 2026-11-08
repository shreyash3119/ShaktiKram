-- Stage 4 security: new tables and views are closed to anon and to non-owners; suggestions are owner only; records are read-only.
begin;
do $$ begin
  assert has_function_privilege('authenticated', 'api_daily_briefing(date)', 'execute') and not has_function_privilege('anon', 'api_daily_briefing(date)', 'execute');
  assert has_function_privilege('authenticated', 'api_next_targets(uuid[],date)', 'execute') and not has_function_privilege('anon', 'api_next_targets(uuid[],date)', 'execute');
  assert not has_function_privilege('authenticated', 'pfs_next_targets(uuid[],date)', 'execute'), 'internal helpers stay closed';
  assert not has_function_privilege('authenticated', 'pfs_detect_prs(uuid)', 'execute') and not has_function_privilege('authenticated', 'calc_progression(jsonb)', 'execute');
  assert not has_function_privilege('anon', 'pfs_e1rm(numeric,integer)', 'execute');
  insert into achievements (kind, threshold, title, achieved_on) values ('workouts_completed', 1, 'First workout completed', '2026-10-01');
  insert into goals (id, type, title, target_metric, target_value) values (md5('t96:g')::uuid, 'strength', 'x', 'pull_up_reps', 10);
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
  assert (select count(*) from achievements) = 0 and (select count(*) from v_goal_progress) = 0 and (select count(*) from v_working_sets) = 0 and (select count(*) from v_equipment_status) = 0, 'non-owner sees nothing';
  perform t_expect_error('select api_readiness()', 'unauthorized');
  perform t_expect_error('select api_weak_point_suggestions()', 'unauthorized');
end $$;
reset role;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-00000000000a', true);
set local role authenticated;
select api_claim_owner();
do $$ begin
  assert (select count(*) from achievements) = 1 and (select count(*) from v_equipment_status) > 20 and (select count(*) from v_goal_progress) = 3, 'owner reads (two seeded goals and one added)';
  perform t_expect_error($q$insert into personal_records (kind, value, session_id, achieved_on) values ('max_weight', 1, gen_random_uuid(), current_date)$q$, 'permission denied');
  perform t_expect_error($q$update achievements set title = 'x'$q$, 'permission denied');
  perform t_expect_error($q$delete from deload_periods$q$, 'permission denied');
end $$;
rollback;
