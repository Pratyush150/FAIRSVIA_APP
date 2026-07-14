-- Driver background check (Checkr) state on the driver profile.
ALTER TABLE "driver_profiles"
  ADD COLUMN "bgc_status" VARCHAR(12) NOT NULL DEFAULT 'none',
  ADD COLUMN "bgc_candidate_id" TEXT,
  ADD COLUMN "bgc_report_id" TEXT;
