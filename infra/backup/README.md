# Postgres backups

Postgres holds everything durable: trips, payments, refunds and the driver
ledger. Redis is deliberately not backed up — it holds only hot, rebuildable
state (live positions, offers, sessions) and runs with AOF.

## What runs

`pg_backup` in `infra/docker-compose.prod.yml`, once a day at
`BACKUP_HOUR_UTC` (default 21:00 UTC = 02:00 Tashkent):

1. `pg_dump --format=custom` to a `.partial` file
2. `pg_restore --list` over it — a dump that fails this is deleted, never kept
3. rename into `daily/`; Sundays hard-linked into `weekly/`, the 1st into
   `monthly/` (hard links: no extra disk)
4. rotate: 7 daily, 4 weekly, 6 monthly (`KEEP_*` env vars)
5. write `metrics/pg_backup.prom` for node_exporter

A failed run retries hourly. Files live on the host at
`/var/backups/ridevela` (`BACKUP_HOST_DIR`).

**Alert:** `PgBackupStale` (critical) fires when the last verified backup is
over 26 hours old. It cannot fire if a backup has *never* succeeded — the
metric does not exist yet — so after first deploying, confirm one run:

```bash
docker compose -p ubernav_prod -f infra/docker-compose.prod.yml logs pg_backup
ls -l /var/backups/ridevela/daily
```

## Restore

Always restore into a scratch database first, check it, then swap.

```bash
make restore-db DUMP=/var/backups/ridevela/daily/<file>.dump TARGET=ubernav_restore
# check row counts / recent trips in ubernav_restore, then point
# DATABASE_URL at it (or rename databases) with the backend stopped.
```

## Verified

2026-09-23, against the dev database: 69 MB database → 12 MB dump; restored
into a scratch database with **identical row counts in all 24 tables (230,381
rows)**. The staleness alert was loaded, stayed inactive on a fresh backup, and
went to pending when the timestamp was set two days back.

## Not done — needs a decision, not code

- **No off-box copy.** Backups on the same disk as the database do not survive
  losing that disk. Needs a destination (object storage bucket or a second
  server). Where it may live depends on the launch country's data-residency
  rules. Uzbekistan's personal-data law (Art. 27-1, in force since 2021)
  requires citizens' personal data to be stored on servers physically inside
  Uzbekistan — confirm with local counsel before choosing a foreign cloud
  region for backups or the database itself.
- **No point-in-time recovery.** Nightly dumps mean up to 24 h of data loss in
  the worst case. WAL archiving (pgBackRest / WAL-G) closes that gap once there
  is an off-box destination to archive to.
