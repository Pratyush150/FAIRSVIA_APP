-- AlterTable
ALTER TABLE "trips" ADD COLUMN     "payment_method_id" UUID;

-- CreateTable
CREATE TABLE "payment_refunds" (
    "id" UUID NOT NULL,
    "payment_id" UUID NOT NULL,
    "trip_id" UUID NOT NULL,
    "amount" DECIMAL(10,2) NOT NULL,
    "status" VARCHAR(12) NOT NULL DEFAULT 'pending',
    "reason" TEXT,
    "external_refund_id" TEXT,
    "failure_message" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "payment_refunds_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "payment_refunds_payment_id_idx" ON "payment_refunds"("payment_id");

-- CreateIndex
CREATE INDEX "payment_refunds_trip_id_idx" ON "payment_refunds"("trip_id");

-- AddForeignKey
ALTER TABLE "payment_refunds" ADD CONSTRAINT "payment_refunds_payment_id_fkey" FOREIGN KEY ("payment_id") REFERENCES "payments"("id") ON DELETE CASCADE ON UPDATE CASCADE;
