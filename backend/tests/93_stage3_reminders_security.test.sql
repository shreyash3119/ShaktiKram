-- Stage 3: reminder rule format and due queries, plus security of the new tables, views and functions.
begin;
do $$
declare sa uuid := md5('t:supp-active')::uuid; sb uuid := md5('t:supp-paused')::uuid;
begin
  perform t_expect_error($q$insert into reminder_rules (kind, label, schedule) values ('water', 'x', '{"type":"hourly","time":"10:00"}')$q$, 'ck_reminder_rules_schedule_valid');
  perform t_expect_error($q$insert into reminder_rules (kind, label, schedule) values ('water', 'x', '{"type":"weekly","time":"10:00"}')$q$, 'ck_reminder_rules_schedule_valid');
  perform t_expect_error($q$insert into reminder_rules (kind, label, schedule) values ('water', 'x', '{"type":"daily","time":"25:00"}')$q$, 'ck_reminder_rules_schedule_valid');
  perform t_expect_error($q$insert into reminder_rules (kind, label, schedule) values ('water', 'x', '{"type":"once","time":"10:00"}')$q$, 'ck_reminder_rules_schedule_valid');
  insert into reminder_rules (kind, label) values ('water', 'not scheduled yet');

  insert into reminder_rules (id, kind, label, schedule) values
    (md5('t:water')::uuid, 'water', 'Water', '{"type":"daily","time":"11:00"}'),
    (md5('t:gym')::uuid, 'workout', 'Gym', '{"type":"weekly","time":"17:30","days":[1,3]}'),
    (md5('t:once')::uuid, 'break_end', 'Break ends', '{"type":"once","time":"08:00","date":"2026-10-06"}'),
    (md5('t:reassess')::uuid, 'reassessment', 'Reassess', '{"type":"daily","time":"10:00"}');
  insert into supplements (id, name) values (sa, 'Active supp (t)'), (sb, 'Paused supp (t)');
  perform pfs_new_version('supplement_phases', jsonb_build_object('entity_id', sa, 'effective_from', '2026-10-01T00:00:00Z', 'status', 'active'), 'start');
  perform pfs_new_version('supplement_phases', jsonb_build_object('entity_id', sb, 'effective_from', '2026-10-01T00:00:00Z', 'status', 'paused'), 'pause');
  insert into reminder_rules (id, kind, label, schedule, linked_table, linked_record_id) values
    (md5('t:sa')::uuid, 'supplement', 'Active', '{"type":"daily","time":"09:00"}', 'supplements', sa),
    (md5('t:sb')::uuid, 'supplement', 'Paused', '{"type":"daily","time":"09:00"}', 'supplements', sb);
  insert into planned_breaks (title, start_date, end_date, mode) values ('Exam day', '2026-10-07', '2026-10-07', 'full');
end $$;

select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-00000000000a', true);
set local role authenticated;
select api_claim_owner();
do $$
declare r jsonb;
  cnt text := $f$select count(*) from jsonb_array_elements(%L::jsonb -> 'data' -> 'reminders') e where e ->> 'rule_id' = %L$f$;
  c int;
begin
  r := api_due_reminders('2026-10-05T00:00:00Z', '2026-10-08T00:00:00Z');
  execute format(cnt, r, md5('t:water')::uuid) into c;      assert c = 3, 'daily water reminder fires 3 times: ' || c;
  execute format(cnt, r, md5('t:gym')::uuid) into c;        assert c = 1, 'gym reminder skips the break day (Mon only): ' || c;
  execute format(cnt, r, md5('t:once')::uuid) into c;       assert c = 1, 'one-off reminder fires once: ' || c;
  execute format(cnt, r, md5('t:sa')::uuid) into c;         assert c = 3, 'active supplement reminds: ' || c;
  execute format(cnt, r, md5('t:sb')::uuid) into c;         assert c = 0, 'paused supplement does not remind: ' || c;
  execute format(cnt, r, md5('t:reassess')::uuid) into c;   assert c = 3, 'reassessment reminder fires while due: ' || c;
  assert r -> 'data' -> 'reminders' -> 0 ->> 'fire_at' is not null;
  perform t_expect_error($q$select api_due_reminders('2026-10-05T00:00:00Z', '2026-10-20T00:00:00Z')$q$, 'validation_failed');
  perform t_expect_error($q$select api_due_reminders('2026-10-05T00:00:00Z', '2026-10-04T00:00:00Z')$q$, 'validation_failed');
end $$;
reset role;

-- a pause and a recent assessment change the answer
update reminder_rules set paused_until = '2026-10-05' where id = md5('t:water')::uuid;
insert into muscle_assessments (occurred_at, local_date, tz_offset_minutes)
  values (date_trunc('day', now()) + interval '12 hours', ((date_trunc('day', now()) + interval '12 hours') at time zone 'UTC' + interval '330 minutes')::date, 330);
set local role authenticated;
do $$
declare r jsonb; c int;
  cnt text := $f$select count(*) from jsonb_array_elements(%L::jsonb -> 'data' -> 'reminders') e where e ->> 'rule_id' = %L$f$;
begin
  r := api_due_reminders('2026-10-05T00:00:00Z', '2026-10-08T00:00:00Z');
  execute format(cnt, r, md5('t:water')::uuid) into c;      assert c = 2, 'paused through 5 Oct: ' || c;
  execute format(cnt, r, md5('t:reassess')::uuid) into c;   assert c = 0, 'no reassessment reminder when nothing is due: ' || c;
end $$;
reset role;

-- security of the new objects
do $$ begin
  assert has_function_privilege('authenticated', 'api_due_reminders(timestamptz,timestamptz)', 'execute');
  assert not has_function_privilege('anon', 'api_due_reminders(timestamptz,timestamptz)', 'execute');
  assert not has_function_privilege('anon', 'api_restriction_warnings(uuid[],date)', 'execute');
  assert not has_function_privilege('authenticated', 'pfs_valid_schedule(jsonb)', 'execute'), 'internal helper stays closed';
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
  assert (select count(*) from supplements) = 0 and (select count(*) from v_muscle_ratings) = 0 and (select count(*) from v_supplement_summary) = 0, 'non-owner sees nothing';
  perform t_expect_error($q$select api_due_reminders('2026-10-05T00:00:00Z', '2026-10-06T00:00:00Z')$q$, 'unauthorized');
end $$;
reset role;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-00000000000a', true);
set local role authenticated;
do $$ begin
  assert (select count(*) from v_muscle_ratings) = 29 and (select count(*) from supplements) = 2, 'owner reads';
  perform t_expect_error($q$insert into water_logs (amount_ml, occurred_at, local_date, tz_offset_minutes) values (100, now(), current_date, 0)$q$, 'permission denied');
  perform t_expect_error($q$update injuries set status = 'resolved'$q$, 'permission denied');
  perform t_expect_error($q$delete from meals$q$, 'permission denied');
end $$;
rollback;
