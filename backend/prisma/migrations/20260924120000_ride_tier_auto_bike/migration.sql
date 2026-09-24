-- Pune pilot: auto-rickshaw and bike-taxi ride types.
-- Additive only: two new RideTier values. Existing trips and driver profiles
-- keep their tiers. The fare_config rows for the new tiers are seeded at boot
-- by PricingService.seedMissing in the market's currency (INR: the Pune RTA
-- auto meter and the Maharashtra bike-taxi fare; see fare-config.ts), and
-- never overwrite a row an admin has tuned.
-- PostgreSQL 12+ allows ADD VALUE inside a transaction (we run 16).
ALTER TYPE "RideTier" ADD VALUE IF NOT EXISTS 'auto';
ALTER TYPE "RideTier" ADD VALUE IF NOT EXISTS 'bike';
