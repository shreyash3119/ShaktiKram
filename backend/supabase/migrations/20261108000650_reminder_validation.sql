-- Stage 3 / reminder rule format. Delivery stays on the device (D10); the backend only checks the rule shape.
-- schedule: {} (not scheduled yet) or {"type":"daily|weekly|once","time":"HH:MM","days":[1..7],"date":"YYYY-MM-DD"}
create function pfs_valid_schedule(s jsonb) returns boolean language sql immutable as $$
  select s = '{}'::jsonb or coalesce(
    jsonb_typeof(s) = 'object' and s ->> 'type' in ('daily', 'weekly', 'once')
    and (s ->> 'time') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    and (s ->> 'type' <> 'weekly' or (jsonb_typeof(s -> 'days') = 'array' and jsonb_array_length(s -> 'days') > 0))
    and (s ->> 'type' <> 'once' or (s ->> 'date') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'), false)
$$;
alter table reminder_rules add constraint ck_reminder_rules_schedule_valid check (pfs_valid_schedule(schedule));
