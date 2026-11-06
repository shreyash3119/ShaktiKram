-- Restore mode keeps ids, revs and timestamps; the revision sequence is moved past the restored data.
begin;
do $$
declare gid constant uuid := '018f0000-0000-7000-8000-0000000000aa'; g goals%rowtype; m bigint; n goals%rowtype;
begin
  perform set_config('pfs.restore_mode', 'on', true);
  insert into goals (id, type, title, start_date, rev, created_at, updated_at, device_id)
  values (gid, 'strength', 'Restored', '2026-01-01', 5000000, '2025-01-01', '2025-02-02', 'dddddddd-0000-0000-0000-000000000001');
  perform set_config('pfs.restore_mode', 'off', true);
  select * into g from goals where id = gid;
  assert g.rev = 5000000 and g.created_at = '2025-01-01' and g.updated_at = '2025-02-02' and g.device_id = 'dddddddd-0000-0000-0000-000000000001', 'restored values kept';
  assert not exists (select 1 from audit_log where record_id = gid) and not exists (select 1 from goal_status_events where goal_id = gid), 'restore writes no audit or events of its own';
  m := pfs_restore_finish();
  assert m = 5000000, 'max rev found: ' || m;
  insert into goals (type, title) values ('strength', 'After restore') returning * into n;
  assert n.rev > 5000000, 'sequence moved past restored data';
  assert exists (select 1 from audit_log where action = 'restore'), 'restore finish is audited';
end $$;

-- a signed-in client can never switch restore mode on: the API turns it off
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-00000000000a', true);
set local role authenticated;
select api_claim_owner();
select api_register_device('d1111111-0000-0000-0000-000000000001', 'Test phone', 'mobile');
select set_config('pfs.restore_mode', 'on', true);
select api_apply_operations('d1111111-0000-0000-0000-000000000001', gen_random_uuid(), jsonb_build_array(
  jsonb_build_object('op_id', gen_random_uuid(), 'seq', 1, 'entity', 'goals', 'action', 'upsert', 'record_id', '018f0000-0000-7000-8000-0000000000bb', 'payload', jsonb_build_object('type', 'strength', 'title', 'Via API'))));
reset role;
do $$ begin
  assert (select rev from goals where id = '018f0000-0000-7000-8000-0000000000bb') > 5000000, 'rev assigned normally even though the flag was on';
  assert exists (select 1 from audit_log where record_id = '018f0000-0000-7000-8000-0000000000bb' and action = 'insert'), 'audit still written';
end $$;
rollback;
