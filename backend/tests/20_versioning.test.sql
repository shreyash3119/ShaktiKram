-- Versioned plans: close and open, ordering, immutability, one current version.
begin;
do $$
declare pid constant uuid := md5('profile')::uuid; v1 profile_versions%rowtype; v2 uuid; v2r profile_versions%rowtype; h numeric;
begin
  select * into v1 from profile_versions where entity_id = pid and version = 1;
  assert v1.effective_to is null and v1.height_cm = 172, 'seed has one current version';

  v2 := pfs_new_version('profile_versions', jsonb_build_object('entity_id', pid, 'effective_from', '2026-11-01T00:00:00Z', 'height_cm', 173, 'body_weight_kg', 77.0), 'new measurements');
  select * into v2r from profile_versions where id = v2;
  assert v2r.version = 2 and v2r.previous_version_id = v1.id and v2r.effective_to is null, 'next version linked';
  assert (select effective_to from profile_versions where id = v1.id) = '2026-11-01T00:00:00Z', 'previous version closed at the new start';
  assert exists (select 1 from audit_log where record_id = v1.id and action = 'version_close'), 'close is audited as version_close';

  -- history answers "what applied then?"
  select height_cm into h from profile_versions where entity_id = pid and effective_from <= '2026-10-15' and (effective_to is null or '2026-10-15' < effective_to);
  assert h = 172, 'as of October the old profile applied';
  select height_cm into h from profile_versions where entity_id = pid and effective_from <= '2026-11-02' and (effective_to is null or '2026-11-02' < effective_to);
  assert h = 173, 'as of November the new profile applies';

  -- rules
  perform t_expect_error(format('select pfs_new_version(''profile_versions'', %L::jsonb, ''x'')', jsonb_build_object('entity_id', pid, 'effective_from', '2026-10-01T00:00:00Z')), 'version_conflict');
  perform t_expect_error(format('update profile_versions set height_cm = 180 where id = %L', v1.id), 'immutable_record');
  perform t_expect_error(format('update profile_versions set effective_to = ''2026-12-01'' where id = %L', v1.id), 'immutable_record');
  perform t_expect_error(format('update profile_versions set effective_to = ''2026-10-01'' where id = %L', v2), 'version_conflict');
  perform t_expect_error(format('insert into profile_versions (entity_id, version, effective_from, effective_to) values (%L, 99, ''2026-09-10'', ''2026-09-20'')', pid), 'ex_profile_versions_no_overlap');
  perform t_expect_error(format('select pfs_new_version(''profile_versions'', %L::jsonb, ''x'')', jsonb_build_object('entity_id', gen_random_uuid(), 'effective_from', '2026-12-01T00:00:00Z')), 'uq_profile_versions_one_current');
  perform t_expect_error('select pfs_new_version(''goals'', ''{}''::jsonb, ''x'')', 'validation_failed');
end $$;
rollback;
