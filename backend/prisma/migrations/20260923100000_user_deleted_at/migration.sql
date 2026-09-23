-- Self-service account deletion (App Store / Play requirement).
ALTER TABLE "users" ADD COLUMN "deleted_at" TIMESTAMPTZ(6);
