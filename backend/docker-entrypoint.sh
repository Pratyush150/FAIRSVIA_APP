#!/usr/bin/env bash
set -e

echo "[entrypoint] Waiting for Postgres to accept connections..."
# Simple retry loop using prisma db push (it fails until DB is reachable).
until npx prisma db push --skip-generate --accept-data-loss 2>/dev/null; do
  echo "[entrypoint] Postgres not ready yet, retrying in 2s..."
  sleep 2
done

echo "[entrypoint] Schema synced. Ensuring Prisma client is generated..."
npx prisma generate >/dev/null 2>&1 || true

echo "[entrypoint] Starting backend: $*"
exec "$@"
