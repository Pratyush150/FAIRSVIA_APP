-- Real SOS: emergency contacts and a tracked incident per SOS press.
-- CreateTable
CREATE TABLE "emergency_contacts" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "name" VARCHAR(80) NOT NULL,
    "phone" VARCHAR(20) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "emergency_contacts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "safety_incidents" (
    "id" UUID NOT NULL,
    "trip_id" UUID NOT NULL,
    "raised_by_id" UUID NOT NULL,
    "raised_by_role" VARCHAR(10) NOT NULL,
    "lat" DOUBLE PRECISION,
    "lng" DOUBLE PRECISION,
    "status" VARCHAR(12) NOT NULL DEFAULT 'open',
    "contacts_total" INTEGER NOT NULL DEFAULT 0,
    "contacts_notified" INTEGER NOT NULL DEFAULT 0,
    "acknowledged_by_id" UUID,
    "acknowledged_at" TIMESTAMPTZ(6),
    "resolved_at" TIMESTAMPTZ(6),
    "note" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "safety_incidents_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "emergency_contacts_user_id_idx" ON "emergency_contacts"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "emergency_contacts_user_id_phone_key" ON "emergency_contacts"("user_id", "phone");

-- CreateIndex
CREATE INDEX "safety_incidents_status_created_at_idx" ON "safety_incidents"("status", "created_at" DESC);

-- CreateIndex
CREATE INDEX "safety_incidents_trip_id_idx" ON "safety_incidents"("trip_id");

-- AddForeignKey
ALTER TABLE "emergency_contacts" ADD CONSTRAINT "emergency_contacts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "safety_incidents" ADD CONSTRAINT "safety_incidents_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE CASCADE;

