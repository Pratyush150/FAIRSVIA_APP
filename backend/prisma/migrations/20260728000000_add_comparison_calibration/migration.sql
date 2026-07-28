-- CreateTable
CREATE TABLE "competitor_fare_models" (
    "provider" VARCHAR(20) NOT NULL,
    "display_name" VARCHAR(40) NOT NULL,
    "product_name" VARCHAR(40) NOT NULL,
    "base_fare" DOUBLE PRECISION NOT NULL,
    "per_mile" DOUBLE PRECISION NOT NULL,
    "per_min" DOUBLE PRECISION NOT NULL,
    "booking_fee" DOUBLE PRECISION NOT NULL,
    "min_fare" DOUBLE PRECISION NOT NULL,
    "surge_sensitivity" DOUBLE PRECISION NOT NULL,
    "calibrated" BOOLEAN NOT NULL DEFAULT false,
    "sample_count" INTEGER NOT NULL DEFAULT 0,
    "residual_pct" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "competitor_fare_models_pkey" PRIMARY KEY ("provider")
);

-- CreateTable
CREATE TABLE "fare_samples" (
    "id" UUID NOT NULL,
    "provider" VARCHAR(20) NOT NULL,
    "market" VARCHAR(40) NOT NULL DEFAULT 'miami',
    "distance_m" INTEGER NOT NULL,
    "duration_s" INTEGER NOT NULL,
    "observed_fare" DOUBLE PRECISION NOT NULL,
    "surge_at_sample" DOUBLE PRECISION NOT NULL DEFAULT 1,
    "hour_bucket" INTEGER NOT NULL DEFAULT 0,
    "source" VARCHAR(20) NOT NULL DEFAULT 'manual',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "fare_samples_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "fare_samples_provider_market_idx" ON "fare_samples"("provider", "market");

