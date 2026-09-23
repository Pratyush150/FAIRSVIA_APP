# RideVela monitoring stack

Prometheus + Grafana + Alertmanager + Loki, plus the Postgres, Redis and host
exporters. Opt-in and separate from the app stack: bringing it up or down never
touches a running backend.

```bash
cd infra/monitoring
docker compose -f docker-compose.monitoring.yml up -d
```

| Service | URL | Notes |
| --- | --- | --- |
| Grafana | http://localhost:3001 | `admin` / `ridevela` — **change this on first login** |
| Prometheus | http://localhost:9099 | 9090 is taken by `tools/webserve.py` |
| Alertmanager | http://localhost:9093 | no delivery configured yet — see below |
| Loki | http://localhost:3100 | queried through Grafana, not directly |

## Dashboards

Provisioned from `grafana/dashboards/*.json`, in the **RideVela** folder.

| Dashboard | Answers |
| --- | --- |
| **Ops** | Is the marketplace working *right now*. Start here in an incident. |
| **Business** | Is the business working. Answered from Postgres, not Prometheus. |
| **Infrastructure** | Is the box ok. Disk leads, because it is the tightest resource here. |

Dashboards are version-controlled files, not UI state. Editing one in the
browser works and is the right way to explore; anything worth keeping gets
exported back into `grafana/dashboards/` and committed. `allowUiUpdates: true`
means Grafana will not fight you while you explore.

## Alerts

11 rules in `prometheus/alerts.yml`. Every threshold comes from the load sweep
of 2026-09-17/18 (`tools/load-test/README.md`) rather than a generic default —
an alert tuned to someone else's system is noise, and noise gets muted.

**Alertmanager has no delivery integration configured on purpose.** One pointed
at a dead webhook looks exactly like one that works, and you find out during the
outage it failed to page for. Fill in the Slack or SES block in
`alertmanager/alertmanager.yml` and restart the container. Until then, firing
alerts are visible in the Alertmanager UI and in Grafana.

## Disk

This host runs near capacity, so both stores are capped:

- Prometheus: 30 days **and** 8 GB, whichever comes first. The size cap is the
  one that actually protects the disk.
- Loki: 7 days.

Run `docker system prune` if space is tight — the plan measured ~40 GB
reclaimable in unused images.

## Why there is no cAdvisor

Docker on this host uses the newer `overlayfs` storage driver. cAdvisor (through
v0.52) still looks for `/var/lib/docker/image/overlay2/layerdb`, fails to
identify any container's read-write layer, and therefore registers **no**
containers at all — it exposes host cgroup series with no `name` label and
nothing else. `--disable_metrics=disk,diskIO` does not help; the failure is in
container registration, not metric collection.

Nothing is lost. Per-service CPU and memory come from better sources already
here: the backend's own `process_*` and `nodejs_*` metrics (including event-loop
lag, which cAdvisor could never have shown), `postgres_exporter`,
`redis_exporter`, and `node_exporter` for host totals.

## Adding a backend replica

Add it to `prometheus/prometheus.yml` **by address**, one target per replica.
Do not point the scraper at nginx: it uses `ip_hash` for Socket.IO session
affinity, which would pin the scraper to one replica and silently halve the
data while looking perfectly healthy.

## Public access to Grafana (pilot, 2026-09-23)

Grafana is reachable from any network through a Cloudflare quick tunnel
(container `ridevela_grafana_tunnel`, on the monitoring network, pointing at
`http://grafana:3000`). Its address changes if the container restarts; get the
current one with:

    docker logs ridevela_grafana_tunnel 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1

- Login is required (anonymous access is off). The default `admin/ridevela`
  password was replaced with a strong one before the link was opened;
  `GF_SECURITY_ADMIN_PASSWORD` in the compose file only applies to a brand-new
  `grafana_data` volume, so wiping that volume brings the weak default back —
  change it again before re-opening the link.
- Team members use the `team` account (Viewer: dashboards only, no editing,
  no ad-hoc queries). Passwords are held by the owner, never in this repo.
- The permanent version is a named tunnel on the RideVela Cloudflare account
  (e.g. `grafana.ridevela.com`) with Cloudflare Access in front.
