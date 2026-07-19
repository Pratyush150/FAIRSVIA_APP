-- AlterTable
ALTER TABLE "driver_profiles" ADD COLUMN     "payouts_enabled" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "stripe_account_id" VARCHAR(64);

-- AlterTable
ALTER TABLE "payments" ADD COLUMN     "idempotency_key" VARCHAR(64);

-- AlterTable
ALTER TABLE "users" ADD COLUMN     "stripe_customer_id" VARCHAR(64);

-- CreateTable
CREATE TABLE "webhook_events" (
    "id" VARCHAR(64) NOT NULL,
    "type" VARCHAR(60) NOT NULL,
    "processed_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "webhook_events_pkey" PRIMARY KEY ("id")
);
