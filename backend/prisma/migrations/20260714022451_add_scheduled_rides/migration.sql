-- AlterEnum
ALTER TYPE "TripStatus" ADD VALUE 'scheduled';

-- AlterTable
ALTER TABLE "trips" ADD COLUMN     "scheduled_at" TIMESTAMPTZ(6);
