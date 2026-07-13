# UberNav load tests

Two Node-based load generators that drive the **real** backend (REST + WebSockets
+ Redis + BullMQ + Postgres). Both print latency percentiles and exit non-zero if
they breach their SLOs, so they can gate a release.

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

## Reference results (single self-hosted box)

| Scenario | Result |
|---|---|
| REST, 75 VUs × 20s | ~3,500 req/s, estimate p95 ≈ 37 ms, 0 errors |
| Ride, 60 drivers / 25 concurrent / 150 rides | 100% matched & completed, match p95 ≈ 450 ms |
| Ride, 150 drivers / 60 concurrent / 600 rides | 100% matched & completed, ~129 rides/s, match p95 ≈ 300 ms |
| Ride, 250 drivers / 120 concurrent / 1000 rides | 93% matched, p50 ≈ 660 ms but p95 ≈ 15 s — the ceiling (also generator-bound) |

> Load testing first surfaced a dispatch ceiling: with a 20-job worker pool the
> 60-concurrent run backed up (match p95 ≈ 18 s, ~2 rides/s). Since a dispatch
> job is I/O-wait, not CPU, widening the pool to 100 and tightening the
> response poll to 100 ms fixed it (match p95 ≈ 300 ms, ~129 rides/s) — a ~26×
> throughput gain. Re-run these tests after touching the dispatch path.

**Caveats:** the generator is a single Node process, so at very high concurrency
it (not the backend) can become the bottleneck — its own event loop drives every
driver+rider socket. For true multi-hundred-concurrent numbers, shard the
generator across several processes/hosts. "Few hundred concurrent" in the project
target means concurrent *connected users*, of which only a fraction request a
ride in the same instant — a burst of dozens of simultaneous new-ride matches is
already a heavy peak for ~10k users.
