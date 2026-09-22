# Monitoring & Ops-Actions Plan

> **New session?** Start with [session-handoff.md](session-handoff.md).

Status: **Phases 1–3 implemented, 2026-09-21.** Phase 4 (Kubernetes) remains a
deliberate "not yet" — see the recommendation at the bottom, which has not
changed.

| Phase | State |
| --- | --- |
| 1 — Blockers | **Done.** Shutdown hooks armed, `/health` split into liveness + readiness (503 when degraded), `audit_log` + a global interceptor keyed on `@Roles(admin)`. |
| 2 — Observability | **Done.** `infra/monitoring/` — Prometheus, Grafana (3 provisioned dashboards), Alertmanager (11 rules, **no delivery wired yet — you must fill one in**), Loki/Promtail, Postgres/Redis/host exporters. Business metrics added to the registry. |
| 3 — Actions | **Done.** Four kill switches (`admin/ops-flags`), enforced in geo, dispatch, surge and payouts, with a confirmed, audited console tab. |
| 4 — Kubernetes | **Not started, by recommendation.** |

Two deviations from the plan as written, both documented at the point of use:

- **cAdvisor is not in the stack.** Docker here uses the newer `overlayfs`
  storage driver, which cAdvisor cannot read; it registers no containers at
  all. Per-service CPU/memory comes from the backend's own `process_*` and
  `nodejs_*` metrics (including event-loop lag) plus the two datastore
  exporters. See `infra/monitoring/README.md`.
- **`/metrics` already existed** and was already wired to an interceptor, so
  2.1 was scrape configuration rather than instrumentation from scratch.

The original plan follows, unchanged.

Grounded in the load-test sweep of 2026-09-17/18 (see
`tools/load-test/README.md` for the measured numbers this plan refers to).

---

## Phase 1 — Blockers (do first, platform-independent) — ~0.5 day

Three defects found while planning. All three must land before any orchestrator,
and two of them matter even on the current Compose setup.

### 1.1 Shutdown hooks are written but never armed

`PrismaService`, `RedisService` and all four queue processors
(`dispatch`, `payments`, `notifications`, `scheduled`) implement
`onModuleDestroy`. `src/main.ts` never calls `app.enableShutdownHooks()`, so
NestJS ignores SIGTERM and **none of those hooks run**.

Today this is mostly invisible. Under any rolling deploy it hard-kills pods
mid-dispatch, dropping in-flight offers and WebSockets with no drain.

Fix: call `app.enableShutdownHooks()` in `bootstrap()`, and verify a
`docker stop` drains rather than truncates.

### 1.2 `/health` returns 200 even when degraded

`health.controller.ts` reports `status: "degraded"` with `database: "down"` in
the body but still returns HTTP **200**. Orchestrator probes read status codes,
so a pod with a dead database stays in the load balancer.

Fix: split into two endpoints.

- **Liveness** — is the process alive. No dependency checks. Never fails on a
  downstream blip (wiring readiness to liveness restarts every pod at once —
  a classic self-inflicted outage).
- **Readiness** — can it serve. Checks DB + Redis, returns **503** when not.

### 1.3 No audit log

22 models in `schema.prisma`, none recording admin actions. These write
endpoints already exist and are unrecorded:

| Endpoint | Action |
| --- | --- |
| `PATCH /admin/drivers/:id/verify` | Approve a driver |
| `PATCH /admin/users/:id/active` | Deactivate a user |
| `POST /admin/payments/:tripId/refund` | Refund money |
| `PATCH /admin/surge` | Change surge multipliers |
| `PATCH /admin/fares/:tier` | Change pricing |
| `POST` / `PATCH /admin/promos` | Create/edit promo codes |
| `PATCH /admin/support/tickets/:id` | Edit a support ticket |

Authorization is already correct (`JwtAuthGuard` + `RolesGuard` +
`@Roles(admin)`) — accountability is what's missing.

Fix: an `audit_log` model (actor, action, target, before/after, IP, timestamp)
plus an interceptor on admin write routes. Required before any dashboard gets
action buttons.

---

## Phase 2 — Observability — ~2 days

Four pillars; we currently have part of one.

| Pillar | Have today |
| --- | --- |
| Metrics | `/metrics` endpoint exists, **nothing scrapes it** |
| Logs | pino → stdout, not aggregated |
| Traces | none |
| Alerts | none |

The point of this phase: we have a dashboard someone must look at. We need a
system that watches itself and calls us.

### 2.1 Stack (add to `docker-compose.prod.yml`)

| Component | Role | RAM |
| --- | --- | --- |
| Prometheus | scrape + store metrics | ~1 GB |
| Grafana | dashboards + alert UI | ~256 MB |
| Alertmanager | route alerts out | ~64 MB |
| Loki | log aggregation | ~512 MB |
| Promtail | ship container logs | ~64 MB |
| postgres_exporter | DB metrics | ~32 MB |
| redis_exporter | Redis metrics | ~32 MB |
| node_exporter | host CPU/RAM/disk | ~32 MB |
| cAdvisor | per-container metrics | ~128 MB |

≈ 2.2 GB RAM total. RAM is not the constraint.

> **Disk is.** The box sits at 96% full (40 GB free). Run `docker system prune`
> first (~40 GB reclaimable in unused images + 4.3 GB build cache) and set
> Prometheus retention explicitly, e.g.
> `--storage.tsdb.retention.time=30d`. Prometheus costs ~1–2 GB/month at a 15s
> scrape interval.

Scrape each backend replica **directly**, not through nginx — `ip_hash` would
otherwise pin the scraper to one replica and silently halve the data.

### 2.2 Business metrics to add to `MetricsService`

Current metrics are HTTP-only. `MetricsService` already owns a Prometheus
registry, so this is additive. Much of `admin.service.ts:opsMetrics()` moves
into the registry.

| Metric | Type | Why |
| --- | --- | --- |
| `dispatch_queue_depth` | gauge | **Highest-value single metric.** Load tests showed backlog here moves first |
| `trip_match_duration_seconds` | histogram | the 4s SLO, measured live |
| `trips_total{status}` | counter | funnel: requested → matched → completed |
| `drivers_online{tier}` | gauge | supply side |
| `active_trips` | gauge | compare against the measured 300 ceiling |
| `vendor_request_duration{vendor,status}` | histogram | would have caught 20,370 Google `OVER_QUERY_LIMIT` immediately |
| `payment_failures_total` | counter | revenue-impacting |

Also add `trace_id` to pino logs so an alert links straight to matching logs.

### 2.3 Alert thresholds (from measured behaviour, not guesses)

| Alert | Threshold | Basis |
| --- | --- | --- |
| Match p95 slow | > 2.5 s for 5 min | measured 2.46 s at the 300-ride ceiling |
| Dispatch backlog | waiting > 50 for 2 min | precedes rider-visible failure |
| Vendor quota | Google error rate > 5% | the failure mode actually hit |
| Active trips near ceiling | > 250 | 83% of measured ceiling |
| Disk | > 90% | **already breached at 96%** |
| Error rate | 5xx > 1% for 5 min | standard |
| Payment failures | spike over baseline | revenue |

### 2.4 Dashboards

Three: **Ops** (queue depth, match latency, active trips, online drivers),
**Business** (funnel, revenue, cancellations), **Infrastructure** (CPU/RAM/disk
per service, Postgres connections, Redis memory).

Per-service load shares measured at the 300-ride ceiling, for dashboard
thresholds: backend 73.7, Postgres 13.7, Redis 7.1, OSRM 5.5, Nominatim 0.0
(of 100). Growth per +1 concurrent ride: backend +0.266, Postgres +0.071,
Redis +0.041, OSRM +0.038 CPU points.

---

## Phase 3 — Actions layer — ~2 days

Wire the existing admin endpoints into a console with confirmation dialogs,
audit trail (Phase 1.3) and RBAC.

Kill switches worth having, in priority order:

1. **Force geo fallback off Google** — would have stopped the quota burn
   immediately.
2. **Pause dispatch** in a zone.
3. **Disable surge**.
4. **Freeze payouts**.

Each: one click, confirmation, audited, reversible.

---

## Phase 4 — Kubernetes — ~1 week, optional, later

**Recommendation: not yet.** Measured capacity is ~300 concurrent rides on a
single box, modelling to roughly 25–50k registered users. At 10k customers that
is ~20–30% utilisation. Kubernetes solves no problem we currently have and adds
a control plane, Helm, a registry, secret management and cluster upgrades to
maintain.

What we actually want from it, and the cheaper route available today:

| Want | K8s way | Available now |
| --- | --- | --- |
| Zero-downtime deploys | rolling update | 2 replicas + nginx (already built) + fix 1.1 |
| Self-healing | pod restarts | `restart: unless-stopped` + alerting |
| Scale out | HPA | more replicas in Compose |

Revisit at ~50k users, multi-region, or a contractual uptime SLA.

### If/when we do it

Free options: **k3s** on our own hardware (genuinely free); **Oracle Cloud
Always Free** (4 ARM cores / 24 GB, free forever); GKE (free control plane for
one zonal cluster, pay nodes); DigitalOcean/Linode (free control plane,
~$12–24/mo per node).

Additional requirements beyond Phase 2:

- All of Phase 1, especially 1.1 and 1.2.
- Container registry (GHCR is free for this repo).
- Secrets management — the `.env` approach doesn't translate (Sealed Secrets or
  External Secrets).
- **Session affinity**: nginx `ip_hash` keeps the Socket.IO handshake on one
  replica; in K8s that becomes `sessionAffinity: ClientIP` on the Service.
- Prisma migrations run as a **Job before rollout**, never on pod start, or
  replicas race each other.
- `kube-prometheus-stack` Helm chart replaces the hand-rolled Phase 2 stack.
- **Keep Postgres and Redis outside the cluster** (managed, or a dedicated
  host). Only the stateless backend belongs in K8s.

---

## Order and effort

| Phase | Effort | Blocking? |
| --- | --- | --- |
| 1 — Blockers | 0.5 day | yes — do first |
| 2 — Observability | 2 days | no |
| 3 — Actions | 2 days | needs 1.3 |
| 4 — Kubernetes | 1 week | optional, later |

About a week to a professional setup without Kubernetes.
