
SELECT
    e.name AS exercise,
    COUNT(em.*) AS muscle_links
FROM public.exercises e
LEFT JOIN public.exercise_muscles em
    ON em.exercise_id = e.id
WHERE e.deleted_at IS NULL
GROUP BY e.id, e.name
ORDER BY e.name;
