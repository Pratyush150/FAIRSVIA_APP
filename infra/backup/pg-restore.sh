#!/bin/sh
# Restore a pg-backup.sh dump into a database.
#
#   pg-restore.sh <dump-file> <target-db>
#
# The target is DROPPED and recreated. Restore into a scratch name first
# (e.g. ubernav_restore), check it, and only then swap it in — never restore
# straight over the live database. Uses the standard libpq env vars.
set -eu

dump="${1:?usage: pg-restore.sh <dump-file> <target-db>}"
target="${2:?usage: pg-restore.sh <dump-file> <target-db>}"

pg_restore --list "$dump" >/dev/null

psql -v ON_ERROR_STOP=1 -d postgres -c "DROP DATABASE IF EXISTS \"$target\" WITH (FORCE)"
psql -v ON_ERROR_STOP=1 -d postgres -c "CREATE DATABASE \"$target\""
pg_restore --no-owner --exit-on-error -d "$target" "$dump"
echo "restored $dump -> $target"
