-- CreateTable
CREATE TABLE "fare_config" (
    "tier" VARCHAR(12) NOT NULL,
    "label" VARCHAR(30) NOT NULL,
    "base_fare" DOUBLE PRECISION NOT NULL,
    "per_km" DOUBLE PRECISION NOT NULL,
    "per_min" DOUBLE PRECISION NOT NULL,
    "booking_fee" DOUBLE PRECISION NOT NULL,
    "min_fare" DOUBLE PRECISION NOT NULL,
    "capacity" INTEGER NOT NULL,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "fare_config_pkey" PRIMARY KEY ("tier")
);
