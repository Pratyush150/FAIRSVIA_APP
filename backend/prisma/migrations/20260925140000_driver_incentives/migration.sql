-- Driver incentives: durable offer outcomes (acceptance/cancellation rates),
-- quests and one-time quest awards. Additive only.
-- CreateTable
CREATE TABLE "driver_offer_events" (
    "id" UUID NOT NULL,
    "driver_id" UUID NOT NULL,
    "trip_id" UUID NOT NULL,
    "outcome" VARCHAR(20) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "driver_offer_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "quests" (
    "id" UUID NOT NULL,
    "title" VARCHAR(120) NOT NULL,
    "tiers" "RideTier"[] DEFAULT ARRAY[]::"RideTier"[],
    "target_trips" INTEGER NOT NULL,
    "starts_at" TIMESTAMPTZ(6) NOT NULL,
    "ends_at" TIMESTAMPTZ(6) NOT NULL,
    "bonus_amount" DECIMAL(10,2) NOT NULL,
    "currency" VARCHAR(3) NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "quests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "quest_awards" (
    "id" UUID NOT NULL,
    "quest_id" UUID NOT NULL,
    "driver_id" UUID NOT NULL,
    "amount" DECIMAL(10,2) NOT NULL,
    "ledger_entry_id" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "quest_awards_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "driver_offer_events_driver_id_created_at_idx" ON "driver_offer_events"("driver_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "quests_active_ends_at_idx" ON "quests"("active", "ends_at");

-- CreateIndex
CREATE INDEX "quest_awards_driver_id_idx" ON "quest_awards"("driver_id");

-- CreateIndex
CREATE UNIQUE INDEX "quest_awards_quest_id_driver_id_key" ON "quest_awards"("quest_id", "driver_id");

-- AddForeignKey
ALTER TABLE "quest_awards" ADD CONSTRAINT "quest_awards_quest_id_fkey" FOREIGN KEY ("quest_id") REFERENCES "quests"("id") ON DELETE CASCADE ON UPDATE CASCADE;

