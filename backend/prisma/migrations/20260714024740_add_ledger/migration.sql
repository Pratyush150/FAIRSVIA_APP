-- CreateTable
CREATE TABLE "ledger_entries" (
    "id" UUID NOT NULL,
    "driver_id" UUID NOT NULL,
    "type" VARCHAR(12) NOT NULL,
    "amount" DECIMAL(10,2) NOT NULL,
    "trip_id" UUID,
    "note" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ledger_entries_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ledger_entries_driver_id_created_at_idx" ON "ledger_entries"("driver_id", "created_at" DESC);
