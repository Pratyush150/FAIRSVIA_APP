-- Daily activity for DAU / MAU. No foreign key on purpose: an analytics row
-- must never block deleting or anonymising a user, and it holds no personal
-- data beyond "this id was active on this day".
CREATE TABLE "user_active_days" (
    "user_id" UUID NOT NULL,
    "day" DATE NOT NULL,

    CONSTRAINT "user_active_days_pkey" PRIMARY KEY ("user_id","day")
);

CREATE INDEX "user_active_days_day_idx" ON "user_active_days"("day");
