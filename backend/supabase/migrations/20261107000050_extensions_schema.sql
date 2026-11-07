-- Stage 2 / hardening: keep extension functions out of the public API schema (found by the Stage 1 test run: privilege warnings).
-- Forward-only fix for Stage 1 migration 20261106000100, which created btree_gist in the default schema.
create schema if not exists extensions;
do $$
begin
  if exists (select 1 from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'btree_gist' and n.nspname <> 'extensions') then
    alter extension btree_gist set schema extensions;
  end if;
end $$;
