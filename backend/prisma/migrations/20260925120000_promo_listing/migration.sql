-- Rider-facing Offers: a promo can be listed publicly with a title/description.
-- Additive only; existing codes stay unlisted.
ALTER TABLE "promo_codes" ADD COLUMN     "description" VARCHAR(200),
ADD COLUMN     "listed" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "title" VARCHAR(60);
