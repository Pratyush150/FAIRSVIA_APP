-- AlterTable
ALTER TABLE "payments" ADD COLUMN     "method" VARCHAR(4) NOT NULL DEFAULT 'card';

-- AlterTable
ALTER TABLE "trips" ADD COLUMN     "payment_mode" VARCHAR(4) NOT NULL DEFAULT 'card';
