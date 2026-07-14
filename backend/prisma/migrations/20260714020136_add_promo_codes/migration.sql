-- AlterTable
ALTER TABLE "trips" ADD COLUMN     "promo_code" VARCHAR(24),
ADD COLUMN     "promo_discount" DECIMAL(10,2) NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "promo_codes" (
    "id" UUID NOT NULL,
    "code" VARCHAR(24) NOT NULL,
    "kind" VARCHAR(8) NOT NULL DEFAULT 'flat',
    "value" DECIMAL(10,2) NOT NULL,
    "max_discount" DECIMAL(10,2),
    "min_subtotal" DECIMAL(10,2) NOT NULL DEFAULT 0,
    "usage_limit" INTEGER,
    "used_count" INTEGER NOT NULL DEFAULT 0,
    "per_user_limit" INTEGER NOT NULL DEFAULT 1,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "expires_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "promo_codes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "promo_redemptions" (
    "id" UUID NOT NULL,
    "promo_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "trip_id" UUID,
    "discount" DECIMAL(10,2) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "promo_redemptions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "promo_codes_code_key" ON "promo_codes"("code");

-- CreateIndex
CREATE INDEX "promo_redemptions_promo_id_idx" ON "promo_redemptions"("promo_id");

-- CreateIndex
CREATE INDEX "promo_redemptions_user_id_idx" ON "promo_redemptions"("user_id");

-- AddForeignKey
ALTER TABLE "promo_redemptions" ADD CONSTRAINT "promo_redemptions_promo_id_fkey" FOREIGN KEY ("promo_id") REFERENCES "promo_codes"("id") ON DELETE CASCADE ON UPDATE CASCADE;
