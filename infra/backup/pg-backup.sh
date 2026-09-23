#!/bin/sh
# One Postgres backup: a compressed custom-format pg_dump, integrity-checked,
# then rotated. Runs inside a postgres image (pg_dump matches the server major).
#
# Env: PGHOST PGUSER PGPASSWORD PGDATABASE (standard libpq vars)
#      BACKUP_DIR        default /backups
#      KEEP_DAILY        default 7   daily dumps kept
#      KEEP_WEEKLY       default 4   Sunday dumps kept beyond the dailies
#      KEEP_MONTHLY      default 6   1st-of-month dumps kept beyond those
set -eu

BACKUP_DIR="${BACKUP_DIR:-/backups}"
KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${KEEP_MONTHLY:-6}"
DB="${PGDATABASE:-ubernav}"

mkdir -p "$BACKUP_DIR/daily" "$BACKUP_DIR/weekly" "$BACKUP_DIR/monthly"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$BACKUP_DIR/daily/${DB}-${stamp}.dump"
tmp="$out.partial"

# Write to .partial and rename only after it verifies, so a crash mid-dump can
# never leave a truncated file that looks like a good backup.
pg_dump --format=custom --compress=6 --no-owner --file="$tmp" "$DB"
if ! pg_restore --list "$tmp" >/dev/null 2>&1; then
  echo "backup FAILED integrity check: $tmp" >&2
  rm -f "$tmp"
  exit 1
fi
mv "$tmp" "$out"

# Promote copies (hard links — no extra disk) for the longer tiers.
[ "$(date -u +%u)" = "7" ] && ln -f "$out" "$BACKUP_DIR/weekly/"
[ "$(date -u +%d)" = "01" ] && ln -f "$out" "$BACKUP_DIR/monthly/"

prune() { # dir keep
  ls -1t "$1"/*.dump 2>/dev/null | tail -n +"$(($2 + 1))" | xargs -r rm -f
}
prune "$BACKUP_DIR/daily" "$KEEP_DAILY"
prune "$BACKUP_DIR/weekly" "$KEEP_WEEKLY"
prune "$BACKUP_DIR/monthly" "$KEEP_MONTHLY"

size="$(du -h "$out" | cut -f1)"
echo "backup OK: $out ($size)"

# node_exporter textfile metrics — the PgBackupStale alert reads these. Written
# via rename so a scrape never sees a half-written file.
mkdir -p "$BACKUP_DIR/metrics"
cat > "$BACKUP_DIR/metrics/pg_backup.prom.tmp" <<EOF
# HELP ridevela_pg_backup_last_success_timestamp_seconds Unix time of the last verified Postgres backup.
# TYPE ridevela_pg_backup_last_success_timestamp_seconds gauge
ridevela_pg_backup_last_success_timestamp_seconds $(date -u +%s)
# HELP ridevela_pg_backup_last_size_bytes Size of the last verified Postgres backup.
# TYPE ridevela_pg_backup_last_size_bytes gauge
ridevela_pg_backup_last_size_bytes $(wc -c < "$out")
EOF
mv "$BACKUP_DIR/metrics/pg_backup.prom.tmp" "$BACKUP_DIR/metrics/pg_backup.prom"
