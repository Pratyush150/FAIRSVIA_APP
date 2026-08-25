# RideVela load tests

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

## Reference results (single self-hosted box)

| Scenario | Result |
|---|---|
| REST, 75 VUs × 20s | ~3,500 req/s, estimate p95 ≈ 37 ms, 0 errors |
| Ride, 60 drivers / 25 concurrent / 150 rides | 100% matched & completed, match p95 ≈ 450 ms |
| Ride, 150 drivers / 60 concurrent / 600 rides | 100% matched & completed, ~129 rides/s, match p95 ≈ 300 ms |
| Ride, 250 drivers / 120 concurrent / 1000 rides | 93% matched, p50 ≈ 660 ms but p95 ≈ 15 s — the ceiling (also generator-bound) |
| Spike, 200 drivers / 3 waves of 150 simultaneous | 100% matched, match p95 ≈ 800 ms, each wave clears in ~1.3 s |
| Spike, 300 drivers / 3 waves of 200 simultaneous | 100% matched, match p95 ≈ 1.0 s |

> Load testing first surfaced a dispatch ceiling: with a 20-job worker pool the
> 60-concurrent run backed up (match p95 ≈ 18 s, ~2 rides/s). Since a dispatch
> job is I/O-wait, not CPU, widening the pool to 100 and tightening the
> response poll to 100 ms fixed it (match p95 ≈ 300 ms, ~129 rides/s) — a ~26×
> throughput gain. Re-run these tests after touching the dispatch path.
>
> The spike profile then surfaced a second, subtler bug: dead-socket drivers
> lingered in the matchable pool, so dispatch burned a full 15 s offer TTL per
> ghost and a burst collapsed to ~26% matched, degrading wave-over-wave. Root
> cause: the socket `handleDisconnect` cleanup was gated on `role === 'driver'`,
> but a driver's JWT is minted at login and still says `'rider'` after
> onboarding, so the cleanup never ran and every dropped/closed driver socket
> leaked into the pool. Keying the cleanup off live driver state (`driverTier`)
> instead of the token role evicts them correctly; the same 150-wide burst then
> matched 100% at ~800 ms p95. This also matters in production under any
> connection churn — a driver whose app drops would otherwise keep receiving
> (and silently dropping) offers.

**Caveats:** the generator is a single Node process, so at very high concurrency
it (not the backend) can become the bottleneck — its own event loop drives every
driver+rider socket. For true multi-hundred-concurrent numbers, shard the
generator across several processes/hosts. "Few hundred concurrent" in the project
target means concurrent *connected users*, of which only a fraction request a
ride in the same instant — a burst of dozens of simultaneous new-ride matches is
already a heavy peak for ~10k users.
