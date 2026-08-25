# RideVela Simulation Engine

A structured, scenario-driven **simulation and load engine** that drives the real
backend the way real users would: many riders and drivers as independent actors,
booking and running **road-following** trips against live OSRM routing, over
Socket.IO + REST — then aggregates metrics, checks SLOs, and surfaces failures.

Unlike the older `tools/fake-driver-simulator` (which only puts cars on the map),
this engine models the **full two-sided marketplace under load**: demand arrival
processes, driver accept/decline/ghost behavior, rider cancellations, per-tier
supply/demand, and the dispatch offer cascade — the places real systems break.

## Run

```bash
cd tools/simulation-engine
npm install            # once (socket.io-client)
node run.mjs smoke     # tiny end-to-end sanity
node run.mjs steady    # realistic Poisson demand vs a healthy fleet
node run.mjs spike     # thundering-herd waves
node run.mjs chaos     # hostile: declines, ghosted offers, rider cancels
node run.mjs soak      # sustained closed-loop load (leak/drift detection)
```

Every scenario prints a report and exits non-zero if any SLO fails, so it doubles
as a CI/CD gate. Add `--json <path>` to also write the raw report.

Knobs are env-overridable per run, e.g.:

```bash
DURATION=30 DRIVERS=40 RATE=2 node run.mjs steady
WAVE=50 WAVES=3 DRIVERS=150 node run.mjs spike
ACCEPT_RATE=1 node run.mjs steady     # force all drivers to auto-accept
```

## Architecture

| File | Responsibility |
|---|---|
| `run.mjs` | CLI: parse scenario + flags, run, print report, set exit code |
| `src/config.mjs` | Endpoints, `TIME_SCALE`, tick + drive-speed constants |
| `src/client.mjs` | Unified REST + Socket.IO client, auth/onboarding helpers |
| `src/geo.mjs` | Miami demand hotspots, weighted trips, OSRM routes, along-route drive w/ bearing, tier apportionment |
| `src/rider.mjs` | Rider actor: estimate → book → await match → ride → rate/tip, with cancel behavior |
| `src/driver.mjs` | Driver actor: go online → offer accept/decline/ghost → drive pickup/dropoff → OTP start → complete, honors `trip:cancelled` |
| `src/orchestrator.mjs` | Fleet ramp-up + arrival models (open/closed/batch), in-flight tracking, drain |
| `src/metrics.mjs` | Timers (percentiles), counters, failure taxonomy |
| `src/report.mjs` | Derived rates, SLO checks, Prometheus scrape of the server |
| `src/scenarios.mjs` | The five presets: fleet, behavior, arrival model, SLOs |
| `src/registry.mjs` | In-process rider↔driver OTP coordination |

### Time compression

Actors drive real OSRM geometry but advance `TIME_SCALE`× per tick (default 30×),
so a real 15-minute trip completes in ~30s of wall-clock. Latencies against the
backend (estimate, create, match) are measured in **real** milliseconds and are
not compressed — only simulated driving is.

### Arrival models

- **open** — Poisson arrivals at a target rate for a duration (realistic demand).
- **closed** — a fixed rider pool doing back-to-back rides with think-time.
- **batch** — synchronized waves of simultaneous requests (thundering herd).

## Findings (things the engine caught, and what changed)

The engine was built to find pitfalls, and it did. Each of these was root-caused
and fixed; the scenarios now guard against regressions.

1. **Momentary supply exhaustion → hard `no_drivers`.** Under bursty demand near
   fleet capacity, dispatch gave up after one expanding-ring pass and immediately
   failed the trip, even though a driver freed up seconds later. **Fix:** dispatch
   now keeps the trip in `matching` and **re-sweeps** for a bounded window
   (`MATCH_WINDOW_MS`) before declaring `no_drivers`. Match success under `steady`
   went 84.7% → ~99%.

2. **A single ghosted offer bounds the match-latency tail.** A driver who neither
   accepts nor declines blocks that rider's sequential offer loop for the whole
   `OFFER_TTL`. This is inherent to safe sequential dispatch; the median match
   stays ~100ms. **Change:** `OFFER_TTL` 15s → 10s (snappier ghost recovery, still
   an easy human-tap window), and SLOs now assert the **median** (health) with a
   p95 bound of ~one TTL (the tail).

3. **Match deadline was only enforced between sweeps.** With many ghosting drivers
   in range, one sweep could run *minutes* past the match window, delaying the
   authoritative `no_drivers` past the rider's own timeout. **Fix:** the deadline
   is now checked **between offers**, so the rider always gets an accept or
   `no_drivers` within the window even under heavy non-acceptance (`chaos`).

4. **Rider-cancel-at-assignment race.** The backend already emits `trip:cancelled`
   to a just-assigned driver and returns them to the pool — but the simulator's
   driver wasn't listening, so it drove to a pickup that no longer existed. This
   was a **simulator fidelity gap**, not a backend bug; the driver actor now
   honors `trip:cancelled` and aborts, matching a real driver app.

## Known tail & a future improvement

The match-latency **tail** is dominated by ghosted offers: safe *sequential*
dispatch offers to one driver at a time, so each ghost costs a full `OFFER_TTL`
before moving on. The median is unaffected (~100ms). The bounded re-sweep and
between-offer deadline guarantee correctness and an authoritative outcome within
the window, but they don't shorten a single ghost's cost.

The real tail-killer would be **parallel (broadcast) dispatch** — offer to the
top-N nearest drivers at once, first-accept-wins. The atomic `assign()`
(matching→accepted transitions exactly once) already makes this race-safe, so one
ghost no longer blocks a match. It's a deliberate product change (multiple drivers
see the same offer; all-but-one get "too late"), so it's noted here rather than
done silently. Until then, SLOs bound the tail at ~1–2 `OFFER_TTL`.

## SLO philosophy

With human drivers, a fraction of offers are ghosted, and each costs one
`OFFER_TTL`. So the meaningful health signal is the **median** match time (the
typical rider is matched near-instantly); the p95 tail is legitimately bounded by
~one offer TTL (more under deliberate abuse in `chaos`). SLOs are set to that
reality, so a future failure means a genuine regression — not a physics violation.
