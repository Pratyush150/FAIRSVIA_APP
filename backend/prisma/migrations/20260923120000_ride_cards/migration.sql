-- Admin-managed promotional cards under the ride details.
-- CreateTable
CREATE TABLE "ride_cards" (
    "id" UUID NOT NULL,
    "title" VARCHAR(80) NOT NULL,
    "body" VARCHAR(240) NOT NULL,
    "cta_type" VARCHAR(12) NOT NULL DEFAULT 'none',
    "cta_label" VARCHAR(40),
    "cta_value" VARCHAR(500),
    "active" BOOLEAN NOT NULL DEFAULT true,
    "starts_at" TIMESTAMPTZ(6),
    "ends_at" TIMESTAMPTZ(6),
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "ride_cards_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ride_cards_active_sort_order_idx" ON "ride_cards"("active", "sort_order");

