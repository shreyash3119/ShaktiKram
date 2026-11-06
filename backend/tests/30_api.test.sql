-- api_apply_operations and api_pull_changes: idempotency, ordering, isolation, conflicts, revocation, paging.
begin;
-- table of facts to exercise the append-only rules (stand-in until Stage 2/3 tables exist)
create table t_facts (id uuid primary key default uuid_v7(), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid, value integer not null);
select pfs_attach('t_facts', 'append_only');
create function t_ops(p_dev uuid, p_ops jsonb) returns jsonb language sql as $$
  select api_apply_operations(p_dev, gen_random_uuid(), p_ops) -> 'data' -> 'results' $$;
grant execute on function t_ops(uuid, jsonb) to public;
select set_config('t.expected', (select sum(row_count)::text from pfs_table_fingerprints() where table_name <> 'audit_log'), true);

select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-00000000000a', true);
set local role authenticated;
select api_claim_owner();
select api_register_device('d1111111-0000-0000-0000-000000000001', 'Test phone', 'mobile');
select api_register_device('d2222222-0000-0000-0000-000000000002', 'Second phone', 'mobile');

do $$
declare
  d1 constant uuid := 'd1111111-0000-0000-0000-000000000001'; d2 constant uuid := 'd2222222-0000-0000-0000-000000000002';
  gid constant uuid := '018f0000-0000-7000-8000-0000000000a1'; op1 uuid := gen_random_uuid();
  r jsonb; rev1 bigint; pid constant uuid := md5('profile')::uuid; fid constant uuid := '018f0000-0000-7000-8000-0000000000f1';
  n integer; pages integer := 0; since bigint := 0; seen integer := 0; last_rev bigint := 0; page jsonb; row_ jsonb; deleted_seen boolean := false;
begin
  -- create, then replay the same op_id: second is a duplicate and changes nothing
  r := t_ops(d1, jsonb_build_array(jsonb_build_object('op_id', op1, 'seq', 1, 'entity', 'goals', 'action', 'upsert', 'record_id', gid,
        'payload', jsonb_build_object('type', 'strength', 'title', 'Bench 80'))));
  assert r -> 0 ->> 'result' = 'applied', 'create applied: ' || r::text;
  rev1 := (r -> 0 ->> 'rev')::bigint;
  r := t_ops(d1, jsonb_build_array(jsonb_build_object('op_id', op1, 'seq', 1, 'entity', 'goals', 'action', 'upsert', 'record_id', gid,
        'payload', jsonb_build_object('type', 'strength', 'title', 'CHANGED'))));
  assert r -> 0 ->> 'result' = 'duplicate', 'replayed op_id is a duplicate';
  assert (select title from goals where id = gid) = 'Bench 80', 'replay changed nothing';

  -- ordering by seq, even when sent out of order
  r := t_ops(d1, jsonb_build_array(
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 3, 'entity', 'goals', 'action', 'upsert', 'record_id', gid, 'base_rev', rev1, 'payload', jsonb_build_object('title', 'third')),
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 2, 'entity', 'goals', 'action', 'upsert', 'record_id', gid, 'base_rev', rev1, 'payload', jsonb_build_object('title', 'second'))));
  assert (select title from goals where id = gid) = 'third', 'higher seq applied last';

  -- one failing operation does not undo the others
  r := t_ops(d1, jsonb_build_array(
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 1, 'entity', 'goals', 'action', 'upsert', 'record_id', gen_random_uuid(), 'payload', jsonb_build_object('type', 'strength', 'title', 'ok A')),
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 2, 'entity', 'goals', 'action', 'upsert', 'record_id', gen_random_uuid(), 'payload', jsonb_build_object('type', 'nonsense', 'title', 'bad')),
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 3, 'entity', 'goals', 'action', 'upsert', 'record_id', gen_random_uuid(), 'payload', jsonb_build_object('type', 'strength', 'title', 'ok B'))));
  assert (r -> 0 ->> 'result', r -> 1 ->> 'result', r -> 2 ->> 'result') = ('applied', 'rejected', 'applied'), 'per-operation isolation: ' || r::text;
  assert r -> 1 ->> 'error_code' = 'validation_failed';
  assert exists (select 1 from goals where title = 'ok A') and exists (select 1 from goals where title = 'ok B') and not exists (select 1 from goals where title = 'bad');

  -- protected, unknown and read-only things are refused with the right codes
  r := t_ops(d1, jsonb_build_array(
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 1, 'entity', 'goals', 'action', 'upsert', 'record_id', gen_random_uuid(), 'payload', jsonb_build_object('type', 'strength', 'title', 'x', 'rev', 1)),
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 2, 'entity', 'audit_log', 'action', 'upsert', 'record_id', gen_random_uuid(), 'payload', '{}'),
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 3, 'entity', 'goal_status_events', 'action', 'delete', 'record_id', gen_random_uuid()),
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 4, 'entity', 'goals', 'action', 'delete', 'record_id', gen_random_uuid()),
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 5, 'entity', 'goals', 'action', 'upsert', 'record_id', gen_random_uuid(), 'payload', jsonb_build_object('type', 'strength', 'title', 'x', 'start_date', '2026-01-01', 'target_date', '2025-01-01'))));
  assert (select array_agg(e ->> 'error_code') from jsonb_array_elements(r) e) = array['validation_failed', 'validation_failed', 'validation_failed', 'not_found', 'validation_failed'], 'error codes: ' || r::text;

  -- conflicts: device 2 edits; device 1 then pushes a stale edit
  r := t_ops(d2, jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'seq', 1, 'entity', 'goals', 'action', 'upsert', 'record_id', gid,
        'base_rev', (select rev from goals where id = gid), 'payload', jsonb_build_object('title', 'device 2 edit'))));
  assert r -> 0 ->> 'result' = 'applied';
  r := t_ops(d1, jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'seq', 1, 'entity', 'goals', 'action', 'upsert', 'record_id', gid,
        'base_rev', rev1, 'client_updated_at', now() - interval '1 hour', 'payload', jsonb_build_object('title', 'stale older edit'))));
  assert r -> 0 ->> 'result' = 'conflict' and (select title from goals where id = gid) = 'device 2 edit', 'older stale edit loses';
  r := t_ops(d1, jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'seq', 1, 'entity', 'goals', 'action', 'upsert', 'record_id', gid,
        'base_rev', rev1, 'client_updated_at', now() + interval '1 minute', 'reason', 'later edit wins', 'payload', jsonb_build_object('title', 'device 1 later edit'))));
  assert r -> 0 ->> 'result' = 'applied' and (select title from goals where id = gid) = 'device 1 later edit', 'later stale-based edit wins';
  r := t_ops(d1, jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'seq', 1, 'entity', 'goals', 'action', 'upsert', 'record_id', gid, 'payload', jsonb_build_object('title', 'no base rev'))));
  assert r -> 0 ->> 'result' = 'duplicate', 'a create re-sent for an existing id is ignored';

  -- versioned plans only through new_version
  r := t_ops(d1, jsonb_build_array(
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 1, 'entity', 'profile_versions', 'action', 'new_version', 'record_id', gen_random_uuid(), 'reason', 'backdated', 'payload', jsonb_build_object('entity_id', pid, 'effective_from', '2026-01-01T00:00:00Z')),
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 2, 'entity', 'profile_versions', 'action', 'new_version', 'record_id', gen_random_uuid(), 'reason', 'new weight', 'payload', jsonb_build_object('entity_id', pid, 'effective_from', '2026-11-02T00:00:00Z', 'body_weight_kg', 76.5)),
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 3, 'entity', 'profile_versions', 'action', 'upsert', 'record_id', gen_random_uuid(), 'payload', '{}')));
  assert (select array_agg(e ->> 'result' || ':' || coalesce(e ->> 'error_code', '')) from jsonb_array_elements(r) e) = array['rejected:version_conflict', 'applied:', 'rejected:validation_failed'], 'version ops: ' || r::text;

  -- reference data: seeded rows protected, equipment availability editable, API-created rows are custom
  r := t_ops(d1, jsonb_build_array(
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 1, 'entity', 'muscles', 'action', 'upsert', 'record_id', md5('muscles:rear_delts')::uuid, 'base_rev', (select rev from muscles where key = 'rear_delts'), 'payload', jsonb_build_object('label', 'Renamed')),
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 2, 'entity', 'muscles', 'action', 'upsert', 'record_id', gen_random_uuid(), 'payload', jsonb_build_object('key', 'forearm_extensors', 'group_key', 'arms', 'label', 'Forearm extensors', 'is_custom', false)),
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 3, 'entity', 'equipment', 'action', 'upsert', 'record_id', md5('equipment:barbell')::uuid, 'base_rev', (select rev from equipment where key = 'barbell'), 'payload', jsonb_build_object('is_available_at_gym', false)),
    jsonb_build_object('op_id', gen_random_uuid(), 'seq', 4, 'entity', 'equipment', 'action', 'upsert', 'record_id', md5('equipment:dumbbell')::uuid, 'base_rev', (select rev from equipment where key = 'dumbbell'), 'payload', jsonb_build_object('label', 'Renamed'))));
  assert (select array_agg(e ->> 'result' || ':' || coalesce(e ->> 'error_code', '')) from jsonb_array_elements(r) e) = array['rejected:immutable_record', 'applied:', 'applied:', 'rejected:immutable_record'], 'reference ops: ' || r::text;
  assert (select is_custom from muscles where key = 'forearm_extensors'), 'API-created reference rows are custom';
  assert not (select is_available_at_gym from equipment where key = 'barbell');

  -- append-only facts: duplicate ignored, correction needs the current rev
  r := t_ops(d1, jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'seq', 1, 'entity', 't_facts', 'action', 'upsert', 'record_id', fid, 'payload', jsonb_build_object('value', 8))));
  rev1 := (r -> 0 ->> 'rev')::bigint;
  r := t_ops(d1, jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'seq', 1, 'entity', 't_facts', 'action', 'upsert', 'record_id', fid, 'payload', jsonb_build_object('value', 99))));
  assert r -> 0 ->> 'result' = 'duplicate' and (select value from t_facts where id = fid) = 8, 'fact re-send ignored';
  r := t_ops(d1, jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'seq', 1, 'entity', 't_facts', 'action', 'upsert', 'record_id', fid, 'base_rev', rev1, 'reason', 'typo', 'payload', jsonb_build_object('value', 9))));
  assert r -> 0 ->> 'result' = 'applied' and (select value from t_facts where id = fid) = 9, 'fact correction applied';

  -- soft delete via API
  r := t_ops(d1, jsonb_build_array(jsonb_build_object('op_id', gen_random_uuid(), 'seq', 1, 'entity', 't_facts', 'action', 'delete', 'record_id', fid)));
  assert r -> 0 ->> 'result' = 'applied' and (select deleted_at from t_facts where id = fid) is not null;

  -- pull: ordered, paged, soft-deleted rows included, nothing skipped
  loop
    page := api_pull_changes(d1, since, 7) -> 'data';
    pages := pages + 1;
    for row_ in select * from jsonb_array_elements(page -> 'rows') loop
      assert (row_ ->> 'rev')::bigint > last_rev, 'strictly increasing rev across pages';
      last_rev := (row_ ->> 'rev')::bigint; seen := seen + 1;
      if row_ ->> 'entity' = 't_facts' and row_ -> 'record' ->> 'deleted_at' is not null then deleted_seen := true; end if;
    end loop;
    exit when not (page ->> 'has_more')::boolean;
    since := (page ->> 'next_rev')::bigint;
  end loop;
  assert pages > 1, 'paging happened';
  assert deleted_seen, 'soft-deleted rows are pulled';
  assert seen >= current_setting('t.expected')::integer, format('pull returned %s rows, expected at least %s', seen, current_setting('t.expected'));

  -- revocation
  perform api_revoke_device(d2);
  perform t_expect_error(format('select api_apply_operations(%L, gen_random_uuid(), ''[]'')', d2), 'device_revoked');
  perform t_expect_error(format('select api_pull_changes(%L, 0, 10)', d2), 'device_revoked');
  perform t_expect_error(format('select api_register_device(%L, ''again'', ''mobile'')', d2), 'device_revoked');
  assert jsonb_array_length(api_apply_operations(d1, gen_random_uuid(), '[]') -> 'data' -> 'results') = 0, 'other devices keep working';
  assert (select count(*) from jsonb_array_elements(api_list_devices() -> 'data') e where e ->> 'revoked_at' is not null) = 1;

  -- request limits and unknown device
  perform t_expect_error(format('select api_apply_operations(%L, gen_random_uuid(), ''{}'')', d1), 'validation_failed');
  perform t_expect_error('select api_apply_operations(gen_random_uuid(), gen_random_uuid(), ''[]'')', 'unauthorized');

  -- a different signed-in user is not the owner
  perform set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-0000-0000-00000000000b', true);
  perform t_expect_error(format('select api_apply_operations(%L, gen_random_uuid(), ''[]'')', d1), 'unauthorized');
  perform t_expect_error('select api_claim_owner()', 'unauthorized');
  perform t_expect_error('select api_list_devices()', 'unauthorized');
end $$;

reset role;
do $$ begin
  assert exists (select 1 from audit_log where table_name = 't_facts' and action = 'update' and before = '{"value": 8}'::jsonb and after = '{"value": 9}'::jsonb and reason = 'typo'), 'correction audited with reason';
  assert exists (select 1 from audit_log where table_name = 'goals' and action = 'update' and before = '{"title": "device 2 edit"}'::jsonb and reason = 'later edit wins'), 'overwritten value kept in audit';
  assert (select count(*) from sync_operations where result = 'rejected') >= 5, 'rejections recorded for replay';
end $$;
rollback;
