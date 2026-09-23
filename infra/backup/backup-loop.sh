#!/bin/sh
# Container entrypoint: back up once a day at BACKUP_HOUR_UTC (default 21 =
# 02:00 Tashkent, off-peak). A failed run is retried after an hour instead of
# waiting a full day.
set -u
HOUR="${BACKUP_HOUR_UTC:-21}"

until pg_isready -q; do sleep 5; done

while true; do
  now=$(date -u +%s)
  next=$(date -u -d "$(date -u +%F) ${HOUR}:00:00" +%s)
  [ "$next" -le "$now" ] && next=$((next + 86400))
  sleep $((next - now))
  until /scripts/pg-backup.sh; do
    echo "backup failed; retrying in 1h" >&2
    sleep 3600
  done
done
