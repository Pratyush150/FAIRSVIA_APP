#!/usr/bin/env bash
set -e

echo "[entrypoint] Waiting for Postgres to accept connections..."
# Read-only readiness probe — never mutates the schema.
until echo 'SELECT 1;' | npx prisma db execute --stdin --schema prisma/schema.prisma >/dev/null 2>&1; do
  echo "[entrypoint] Postgres not ready yet, retrying in 2s..."
  sleep 2
done

echo "[entrypoint] Applying migrations (prisma migrate deploy)..."
# Idempotent: applies any pending migrations, no-op when up to date. Fails loudly
# (set -e) on a bad migration instead of silently mutating like 'db push' did.
npx prisma migrate deploy

echo "[entrypoint] Ensuring Prisma client is generated..."
npx prisma generate >/dev/null 2>&1 || true

echo "[entrypoint] Starting backend: $*"
exec "$@"
