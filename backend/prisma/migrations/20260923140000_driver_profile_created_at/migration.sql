-- When someone became a driver, for driver-growth analytics. Existing rows get
-- the migration time: there is no record of when they onboarded.
ALTER TABLE "driver_profiles" ADD COLUMN "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP;
CREATE INDEX "driver_profiles_created_at_idx" ON "driver_profiles"("created_at");
