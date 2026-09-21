# Ride App load tests

Three Node-based load generators that drive the **real** backend (REST + WebSockets
+ Redis + BullMQ + Postgres). Each prints latency percentiles and exits non-zero if
it breaches its SLOs, so they can gate a release.

```bash
cd tools/load-test && npm install

# 1. REST hot path — N virtual users hammer /trips/estimate
CONC=75 DURATION_S=20 npm run rest

# 2. Realistic capacity — a driver fleet + concurrent full rides
DRIVERS=60 CONC=25 RIDES=150 npm run ride
```

Point at another host with `BASE_URL` / `WS_URL` (default `localhost:3000`).

## rest-load.mjs

`/trips/estimate` is the most-called endpoint (every "where to?" triggers one)
and has no side effects, so it cleanly measures API+compute throughput.

Knobs: `CONC` (virtual users), `DURATION_S`, `P95_SLO_MS` (default 600),
`ERR_SLO` (default 0.01).

## ride-load.mjs

Brings up `DRIVERS` drivers (online, streaming GPS every 1s, auto-accepting
offers), connects `CONC` riders, and runs `RIDES` full rides
(create → match → arrived → start(OTP) → complete) with `CONC` in flight. It
exercises the entire hot path including the dispatch queue and the trip state
machine, then reports match-latency + end-to-end percentiles, match success
rate, and completed-ride throughput.

Knobs: `DRIVERS`, `CONC`, `RIDES`, `MATCH_TIMEOUT_MS`, `MATCH_SUCCESS_SLO`
(default 0.95), `MATCH_P95_SLO_MS` (default 4000).

Keep `DRIVERS` comfortably above `CONC` so the fleet isn't starved.

## spike-load.mjs

The synchronized **thundering-herd** profile. Where `ride-load` paces rides
through a fixed worker pool (steady-state throughput), `spike-load` fires an
entire *wave* of ride requests at the same instant — every rider in the batch
calls `POST /trips` simultaneously — then repeats for `WAVES` waves. This is the
demand shape of a real surge (a concert lets out, rain starts) and stresses a
different axis than throughput: dispatch-queue depth, per-driver offer locking,
and Redis GEO contention when hundreds of matches are contended at once.

```bash
DRIVERS=200 WAVE=150 WAVES=3 npm run spike
```

Knobs: `DRIVERS`, `WAVE` (requests fired at once), `WAVES`, `GAP_MS` (pause
between waves), `MATCH_TIMEOUT_MS`, `MATCH_SUCCESS_SLO` (default 0.97),
`MATCH_P95_SLO_MS` (default 4000).

## Reference results

Measured 2026-09-17 on the single self-hosted box (Ryzen 5 7600X, 6c/12t,
30 GB). **Dev stack**: one backend replica running `npm run start:dev`
(TypeScript watch mode), geo on self-hosted OSRM + Nominatim, mock payments.
A compiled build (`Dockerfile.prod`) behind the two-replica prod profile has
not been benchmarked yet and should be meaningfully faster.

| Scenario | Result |
|---|---|
| REST, 75 VUs × 20s | 1,399 req/s, estimate p95 73 ms, 0 errors |
| Ride, 150 drivers / 60 concurrent / 600 rides | 100% matched & completed, 79.5 rides/s, match p95 459 ms, e2e p95 996 ms |
| Ride, 250 drivers / 120 concurrent / 1000 rides | 100% matched & completed, 91.3 rides/s, match p95 849 ms |
| Ride, 400 drivers / 200 concurrent / 1500 rides | 100% matched & completed, 93.8 rides/s, match p95 1469 ms |
| Ride, 600 drivers / 300 concurrent / 2000 rides | 100% matched & completed, 87.1 rides/s, match p95 2178 ms |
| Ride, 1000 drivers / 500 concurrent / 2500 rides | 100% matched, **match p95 5039 ms — SLO breach, the ceiling** |
| Spike, 200 drivers / 3 waves of 150 simultaneous | 100% matched, match p95 1168 ms, each wave clears in ~1.8 s |

Throughput plateaus at **~90 completed rides/s** from 120 concurrent onward;
past that, extra concurrency only adds queueing latency, and the 4 s match SLO
breaks somewhere between **300 and 500 concurrent in-flight rides**. At the
ceiling the backend process is the bottleneck (~270% CPU, i.e. ~2.7 cores) while
Postgres peaks at 52%, Redis at 22% and the host at load 2.7 of 12 threads — so
the limit is one Node process, not the datastores or the machine.

> ### Run these against local providers, not live vendors
>
> The dev `.env` carries a **real Google Maps key and real Stripe key**. Point a
> load test at that stack and it will hammer both: a 20 s REST run produced
> **20,370 `OVER_QUERY_LIMIT` errors** against the live Maps API, which also
> halves measured throughput (749 req/s vs 1,399) because every estimate becomes
> a failed round-trip plus an OSRM fallback. Before a run, clear
> `GOOGLE_MAPS_API_KEY` and `STRIPE_SECRET_KEY` so `geo.module.ts` selects
> OSRM+Nominatim and `payments.module.ts` selects `MockPaymentProvider`. Both
> are read from the compose `env_file` at container **create** time, so
> `docker restart` is not enough — use
> `docker compose -p infra up -d --force-recreate --no-deps backend`.
>
> This also proved the `FallbackGeoProvider` works: 20k upstream failures
> produced zero user-facing errors.

> ### History: three bugs these tests surfaced
>
> **Dispatch pool (backend, fixed).** With a 20-job worker pool the
> 60-concurrent run backed up (match p95 ≈ 18 s, ~2 rides/s). A dispatch job is
> I/O-wait, not CPU, so widening the pool to 100 and tightening the response
> poll to 100 ms fixed it — a ~26× throughput gain. Re-run after touching the
> dispatch path.
>
> **Ghost drivers (backend, fixed).** Dead-socket drivers lingered in the
> matchable pool, so dispatch burned a full 15 s offer TTL per ghost and a burst
> collapsed to ~26% matched. Root cause: `handleDisconnect` cleanup was gated on
> `role === 'driver'`, but a driver's JWT is minted at login and still says
> `'rider'` after onboarding. Keying the cleanup off live driver state
> (`driverTier`) evicts them correctly.
>
> **Rider leak (harness, fixed).** The generators never released a rider whose
> ride didn't reach `complete`. Since the backend allows one live trip per rider
> (`ACTIVE_TRIP_STATUSES`), that rider then 409'd on every later attempt in a
> tight 1–3 ms loop and drained the whole ride queue — which read as a backend
> failure (10% match rate) and produced the bogus "ceiling" previously recorded
> at 120 concurrent. Both generators now cancel on every non-complete path and
> retire a rider they cannot free. The ride generator also drives the matched
> driver to the pickup before marking arrived, because the backend enforces a
> 150 m arrival geofence (`assertNearPickup`) that scattered test drivers
> legitimately fail, and retries once if the fix loses a write race against the
> driver's pool-return location.

**Caveats:** the generator is a single Node process, so at very high concurrency
it (not the backend) can become the bottleneck — its own event loop drives every
driver+rider socket. For true multi-hundred-concurrent numbers, shard the
generator across several processes/hosts. "Few hundred concurrent" in the project
target means concurrent *connected users*, of which only a fraction request a
ride in the same instant — a burst of dozens of simultaneous new-ride matches is
already a heavy peak for ~10k users.
