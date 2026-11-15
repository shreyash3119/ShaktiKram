-- Read-only checks for the exercise catalogue. Safe to run any time in the Supabase SQL Editor.
-- The editor shows only the last result, so run each block separately (select it, then Run selected).

-- 1. Totals
select (select count(*) from exercises where deleted_at is null) as exercises,
       (select count(*) from exercises where deleted_at is null and is_custom = false) as built_in,
       (select count(*) from exercises where deleted_at is null and is_custom) as custom,
       (select count(*) from exercise_muscles where deleted_at is null) as links;

-- 2. Exercises without a primary muscle (expect none)
select e.name from exercises e where e.deleted_at is null
   and not exists (select 1 from exercise_muscles x where x.exercise_id = e.id and x.role = 'primary' and x.deleted_at is null) order by e.name;

-- 3. Exercises with more than one primary (expect none)
select e.name, count(*) as primaries from exercises e join exercise_muscles x on x.exercise_id = e.id and x.role = 'primary' and x.deleted_at is null
 where e.deleted_at is null group by e.name having count(*) > 1;

-- 4. Exercises without equipment (expect none for built-ins; 'bodyweight' is an equipment row)
select name from exercises where deleted_at is null and equipment_id is null order by name;

-- 5. Exercises with NULL category (expect none)
select name from exercises where deleted_at is null and category is null order by name;

-- 6. Duplicate names, any case (expect none; also enforced by uq_exercises_name_alive)
select lower(name) as name, count(*) from exercises where deleted_at is null group by 1 having count(*) > 1;

-- 7. Invalid references (expect none)
select 'exercise_muscles -> exercise' as problem, x.id from exercise_muscles x where not exists (select 1 from exercises e where e.id = x.exercise_id)
union all select 'exercise_muscles -> muscle', x.id from exercise_muscles x where not exists (select 1 from muscles m where m.id = x.muscle_id)
union all select 'exercises -> equipment', e.id from exercises e where e.equipment_id is not null and not exists (select 1 from equipment q where q.id = e.equipment_id)
union all select 'invalid role', x.id from exercise_muscles x where x.role not in ('primary', 'secondary', 'indirect');

-- 8. Count by category
select coalesce(category, '(none)') as category, count(*) from exercises where deleted_at is null group by 1 order by 1;

-- 9. Count by muscle group (primary muscle)
select m.group_key as muscle_group, count(*) as exercises from exercise_muscles x join muscles m on m.id = x.muscle_id
  join exercises e on e.id = x.exercise_id and e.deleted_at is null
 where x.role = 'primary' and x.deleted_at is null group by 1 order by 2 desc;

-- 10. Count by equipment
select coalesce(q.label, '(none)') as equipment, count(*) as exercises from exercises e left join equipment q on q.id = e.equipment_id
 where e.deleted_at is null group by 1 order by 2 desc, 1;

-- 11. Final catalogue, alphabetical
select e.name, e.category, q.label as equipment,
       (select m.label from exercise_muscles x join muscles m on m.id = x.muscle_id where x.exercise_id = e.id and x.role = 'primary' and x.deleted_at is null limit 1) as primary_muscle,
       (select string_agg(m.label, ', ' order by m.label) from exercise_muscles x join muscles m on m.id = x.muscle_id where x.exercise_id = e.id and x.role = 'secondary' and x.deleted_at is null) as secondary_muscles,
       case when e.is_custom then 'custom' else 'built-in' end as kind
  from exercises e left join equipment q on q.id = e.equipment_id where e.deleted_at is null order by lower(e.name);
