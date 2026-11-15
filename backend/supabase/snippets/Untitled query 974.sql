SELECT
    (SELECT COUNT(*) FROM public.exercises WHERE deleted_at IS NULL) AS active_exercises,
    (SELECT COUNT(*) FROM public.muscles WHERE deleted_at IS NULL) AS active_muscles,
    (SELECT COUNT(*) FROM public.exercise_muscles WHERE deleted_at IS NULL) AS active_muscle_links;