-- driver_profiles.created_at was added today with the migration's time for
-- every existing row, so "new drivers today" counted all of them. The best
-- record we have of when they joined is their account sign-up.
UPDATE driver_profiles dp
SET created_at = u.created_at
FROM users u
WHERE u.id = dp.user_id
  AND dp.created_at >= (SELECT finished_at - interval '1 minute' FROM _prisma_migrations WHERE migration_name = '20260923140000_driver_profile_created_at')
  AND dp.created_at <= (SELECT finished_at + interval '1 minute' FROM _prisma_migrations WHERE migration_name = '20260923140000_driver_profile_created_at');
