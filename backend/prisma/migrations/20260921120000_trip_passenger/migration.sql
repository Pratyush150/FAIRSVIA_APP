-- Booking a ride for somebody else: the booker stays `rider_id` (they pay and
-- they track it); these name the person actually travelling. Both NULL for an
-- ordinary ride, which is every row that already exists.
-- AlterTable
ALTER TABLE "trips" ADD COLUMN     "passenger_name" VARCHAR(80);
ALTER TABLE "trips" ADD COLUMN     "passenger_phone" VARCHAR(20);
