-- Stage 1 / sync core: one write function (api_apply_operations) and pull by revision (api_pull_changes).
-- Rules: docs/TECHNICAL_CONTRACT.md section 10. Offline client behaviour is Stage 6.

create table sync_operations (
  op_id uuid primary key,
  device_id uuid not null,
  request_id uuid,
  seq bigint,
  entity text,
  action text,
  record_id uuid,
  result text not null,
  error_code text,
  detail jsonb,
  applied_rev bigint,
  created_at timestamptz not null default now()
);
create index idx_sync_operations_device_id_created_at on sync_operations (device_id, created_at);
select pfs_secure('sync_operations');

create function pfs_error_code(p_state text, p_msg text) returns text language sql immutable as $$
  select case
    when split_part(p_msg, ':', 1) in ('validation_failed','not_found','version_conflict','immutable_record','reference_missing',
                                       'conflict_stale_rev','unauthorized','device_revoked','payload_too_large') then split_part(p_msg, ':', 1)
    when p_state = '23P01' then 'version_conflict'
    when p_state = '23503' then 'reference_missing'
    when p_state like '23%' or p_state like '22%' then 'validation_failed'
    else 'internal_error' end
$$;

create function pfs_check_payload_keys(p_table text, p_payload jsonb) returns void language plpgsql as $$
declare bad text;
begin
  if jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'validation_failed: payload must be an object'; end if;
  select string_agg(k, ', ') into bad from jsonb_object_keys(p_payload) k
   where k in ('rev', 'created_at', 'updated_at', 'device_id', 'deleted_at')
      or k not in (select attname::text from pg_attribute where attrelid = ('public.' || quote_ident(p_table))::regclass and attnum > 0 and not attisdropped);
  if bad is not null then raise exception 'validation_failed: unknown or protected field(s): %', bad; end if;
end $$;

create function pfs_insert_json(p_table text, p_payload jsonb) returns uuid language plpgsql as $$
declare cols text; v_id uuid;
begin
  perform pfs_check_payload_keys(p_table, p_payload);
  select string_agg(quote_ident(k), ', ') into cols from jsonb_object_keys(p_payload) k;
  execute format('insert into %1$I (%2$s) select %2$s from jsonb_populate_record(null::%1$I, $1) returning id', p_table, cols) into v_id using p_payload;
  return v_id;
end $$;

create function pfs_update_json(p_table text, p_id uuid, p_payload jsonb) returns void language plpgsql as $$
declare sets text; v_body jsonb := p_payload - 'id';
begin
  perform pfs_check_payload_keys(p_table, v_body);
  select string_agg(format('%1$I = r.%1$I', k), ', ') into sets from jsonb_object_keys(v_body) k;
  if sets is null then return; end if;
  execute format('update %1$I t set %2$s from jsonb_populate_record(null::%1$I, $2) r where t.id = $1', p_table, sets) using p_id, v_body;
end $$;

-- Closes the current version and opens the next. The only way to change a versioned table.
create function pfs_new_version(p_table text, p_payload jsonb, p_reason text) returns uuid language plpgsql as $$
declare
  reg pfs_registry%rowtype; v_entity uuid := (p_payload ->> 'entity_id')::uuid;
  v_from timestamptz := coalesce((p_payload ->> 'effective_from')::timestamptz, now());
  cur record; v_body jsonb;
begin
  select * into reg from pfs_registry where table_name = p_table;
  if not found or reg.record_class <> 'versioned' then raise exception 'validation_failed: % is not a versioned table', p_table; end if;
  if v_entity is null then raise exception 'validation_failed: entity_id is required'; end if;
  execute format('select id, version, effective_from, effective_to from %I where entity_id = $1 and deleted_at is null order by version desc limit 1', p_table)
    into cur using v_entity;
  if cur.id is not null then
    if cur.effective_to is null then
      if v_from < cur.effective_from then raise exception 'version_conflict: a new version cannot start before the current one'; end if;
      execute format('update %I set effective_to = $1 where id = $2', p_table) using v_from, cur.id;
    elsif v_from < cur.effective_to then
      raise exception 'version_conflict: a new version cannot start before the previous one ended';
    end if;
  end if;
  v_body := p_payload || jsonb_build_object('entity_id', v_entity, 'version', coalesce(cur.version, 0) + 1, 'effective_from', v_from,
              'effective_to', null, 'previous_version_id', cur.id, 'change_reason', p_reason,
              'id', coalesce(p_payload ->> 'id', uuid_v7()::text));
  return pfs_insert_json(p_table, v_body);
end $$;

create function pfs_dispatch(op jsonb) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_entity text := op ->> 'entity'; v_action text := op ->> 'action'; v_rid uuid := (op ->> 'record_id')::uuid;
  v_payload jsonb := coalesce(op -> 'payload', '{}'::jsonb);
  v_base bigint := (op ->> 'base_rev')::bigint;
  v_client timestamptz := least(coalesce((op ->> 'client_updated_at')::timestamptz, now()), now() + interval '5 minutes');
  reg pfs_registry%rowtype; ex_rev bigint; ex_upd timestamptz; ex_dev uuid; v_rev bigint;
  v_dev uuid := nullif(current_setting('pfs.device_id', true), '')::uuid;
begin
  select * into reg from pfs_registry where table_name = v_entity and client_writable;
  if not found then raise exception 'validation_failed: unknown or read-only entity %', v_entity; end if;
  perform set_config('pfs.reason', coalesce(op ->> 'reason', ''), true);

  if v_action = 'new_version' then
    v_rid := pfs_new_version(v_entity, v_payload, op ->> 'reason');
  else
    if v_rid is null then raise exception 'validation_failed: record_id is required'; end if;
    execute format('select rev, updated_at, device_id from %I where id = $1', v_entity) into ex_rev, ex_upd, ex_dev using v_rid;
    if v_action = 'upsert' then
      if reg.record_class = 'versioned' then raise exception 'validation_failed: use new_version for versioned tables'; end if;
      if ex_rev is null then
        perform pfs_insert_json(v_entity, v_payload || jsonb_build_object('id', v_rid));
      else
        -- An edit must name the revision it was based on. Anything else is a re-sent create: ignored.
        if v_base is null or (reg.record_class = 'append_only' and v_base is distinct from ex_rev) then
          return jsonb_build_object('result', 'duplicate', 'rev', ex_rev);
        end if;
        -- A conflict needs a DIFFERENT device to have written the row since base_rev. A device's own earlier edits never conflict.
        if reg.record_class = 'editable' and v_base < ex_rev and ex_dev is distinct from v_dev and v_client <= ex_upd then
          return jsonb_build_object('result', 'conflict', 'rev', ex_rev);   -- server copy is newer: it wins
        end if;
        perform pfs_update_json(v_entity, v_rid, v_payload);
      end if;
    elsif v_action = 'delete' then
      if reg.record_class = 'versioned' then raise exception 'immutable_record: version rows cannot be deleted'; end if;
      if ex_rev is null then raise exception 'not_found: % % does not exist', v_entity, v_rid; end if;
      if reg.record_class = 'editable' and v_base is not null and v_base < ex_rev and ex_dev is distinct from v_dev and v_client <= ex_upd then
        return jsonb_build_object('result', 'conflict', 'rev', ex_rev);
      end if;
      execute format('update %I set deleted_at = now() where id = $1 and deleted_at is null', v_entity) using v_rid;
    else
      raise exception 'validation_failed: unknown action %', v_action;
    end if;
  end if;
  execute format('select rev from %I where id = $1', v_entity) into v_rev using v_rid;
  return jsonb_build_object('result', 'applied', 'rev', v_rev);
end $$;

-- One operation: idempotent, and isolated in its own savepoint so a failure does not undo the others.
create function pfs_apply_op(op jsonb, p_device uuid, p_request uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_op_id uuid; prev sync_operations%rowtype; v_out jsonb; v_result text; v_rev bigint; v_code text; v_msg text;
begin
  begin
    v_op_id := (op ->> 'op_id')::uuid;
  exception when others then
    return jsonb_build_object('op_id', op -> 'op_id', 'result', 'rejected', 'error_code', 'validation_failed', 'message', 'op_id must be a uuid');
  end;
  select * into prev from sync_operations where op_id = v_op_id;
  if found then
    return jsonb_strip_nulls(jsonb_build_object('op_id', v_op_id, 'result', 'duplicate', 'original_result', prev.result,
                                                'error_code', prev.error_code, 'rev', prev.applied_rev));
  end if;
  begin
    v_out := pfs_dispatch(op);
    v_result := v_out ->> 'result';
    v_rev := (v_out ->> 'rev')::bigint;
  exception when others then
    v_result := 'rejected';
    v_msg := sqlerrm;
    v_code := pfs_error_code(sqlstate, sqlerrm);
  end;
  insert into sync_operations (op_id, device_id, request_id, seq, entity, action, record_id, result, error_code, detail, applied_rev)
  values (v_op_id, p_device, p_request, (op ->> 'seq')::bigint, op ->> 'entity', op ->> 'action', (op ->> 'record_id')::uuid,
          v_result, v_code, case when v_msg is not null then jsonb_build_object('message', v_msg) end, v_rev);
  return jsonb_strip_nulls(jsonb_build_object('op_id', v_op_id, 'result', v_result, 'rev', v_rev, 'error_code', v_code, 'message', v_msg));
end $$;

-- THE write interface for phone sync (and any later web edits). Writes are serialised with a lock, so revisions
-- become visible in order and a client pulling "since rev N" can never skip a row.
create function api_apply_operations(p_device_id uuid, p_request_id uuid, p_operations jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare op jsonb; results jsonb := '[]'::jsonb;
begin
  perform pfs_require_device(p_device_id);
  if jsonb_typeof(p_operations) is distinct from 'array' then raise exception 'validation_failed: operations must be an array' using errcode = 'PT422'; end if;
  if jsonb_array_length(p_operations) > 500 then raise exception 'payload_too_large: at most 500 operations per request' using errcode = 'PT413'; end if;
  perform pg_advisory_xact_lock(hashtext('pfs_write'));
  perform set_config('pfs.in_api', 'on', true);
  for op in select e.value from jsonb_array_elements(p_operations) with ordinality e (value, n) order by (e.value ->> 'seq')::bigint, e.n loop
    results := results || jsonb_build_array(pfs_apply_op(op, p_device_id, p_request_id));
  end loop;
  return jsonb_build_object('data', jsonb_build_object('results', results), 'meta', pfs_meta(p_request_id));
end $$;

-- Pull: every change after since_rev across all synced tables, soft-deleted rows included, in revision order.
create function api_pull_changes(p_device_id uuid, p_since_rev bigint default 0, p_limit integer default 200) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_union text; v_rows jsonb; v_n integer; v_limit integer := least(greatest(coalesce(p_limit, 200), 1), 500); v_more boolean := false; v_next bigint;
begin
  perform pfs_require_device(p_device_id);
  if p_since_rev < 0 then raise exception 'validation_failed: since_rev must be 0 or more' using errcode = 'PT422'; end if;
  select string_agg(format('select %L::text as entity, t.rev, to_jsonb(t) as record from %I t where t.rev > $1', table_name, table_name), ' union all ')
    into v_union from pfs_registry;
  execute format('select coalesce(jsonb_agg(x order by x.rev), ''[]''::jsonb) from (select entity, rev, record from (%s) u order by rev limit $2 + 1) x', v_union)
    into v_rows using p_since_rev, v_limit;
  v_n := jsonb_array_length(v_rows);
  if v_n > v_limit then
    v_more := true;
    select jsonb_agg(e.value order by e.ord) into v_rows from jsonb_array_elements(v_rows) with ordinality e (value, ord) where e.ord <= v_limit;
  end if;
  v_next := coalesce((v_rows -> (jsonb_array_length(v_rows) - 1) ->> 'rev')::bigint, p_since_rev);
  update devices set last_pull_rev = greatest(last_pull_rev, v_next) where id = p_device_id;
  return jsonb_build_object('data', jsonb_build_object('rows', v_rows, 'next_rev', v_next, 'has_more', v_more), 'meta', pfs_meta());
end $$;
