-- Localize pricing to USD / per-mile (target market: Florida, US).
-- The distance rate column moves from per-kilometer to per-mile.
ALTER TABLE "fare_config" RENAME COLUMN "per_km" TO "per_mile";

-- The pre-existing rows held INR per-km rates, which are meaningless as USD
-- per-mile rates. Clear the table so PricingService.seedIfEmpty repopulates it
-- with the new USD defaults from fare-config.ts on the next boot.
TRUNCATE TABLE "fare_config";

-- Default currency for new trips/payments is now USD.
ALTER TABLE "trips" ALTER COLUMN "currency" SET DEFAULT 'USD';
ALTER TABLE "payments" ALTER COLUMN "currency" SET DEFAULT 'USD';
