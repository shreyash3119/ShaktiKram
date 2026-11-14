SELECT COUNT(*) AS total_muscles
FROM public.muscles
WHERE deleted_at IS NULL;