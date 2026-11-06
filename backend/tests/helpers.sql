-- Test helpers (test database only, never a migration).
create or replace function t_expect_error(p_sql text, p_expect text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm like '%' || p_expect || '%' then return; end if;
    raise exception 'wrong error for [%]: got [%], wanted [%]', p_sql, sqlerrm, p_expect;
  end;
  raise exception 'expected error [%] but the statement succeeded: %', p_expect, p_sql;
end $$;
grant execute on function t_expect_error(text, text) to public;
