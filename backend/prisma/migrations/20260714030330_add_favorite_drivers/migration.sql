-- CreateTable
CREATE TABLE "favorite_drivers" (
    "id" UUID NOT NULL,
    "rider_id" UUID NOT NULL,
    "driver_id" UUID NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "favorite_drivers_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "favorite_drivers_rider_id_idx" ON "favorite_drivers"("rider_id");

-- CreateIndex
CREATE UNIQUE INDEX "favorite_drivers_rider_id_driver_id_key" ON "favorite_drivers"("rider_id", "driver_id");
