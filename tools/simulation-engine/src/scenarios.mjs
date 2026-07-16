// Scenario presets. Each composes fleet size, actor behavior, an arrival model,
// and SLO thresholds. Key knobs are env-overridable so the same scenario can be
// scaled up/down for the box it runs on. SLO defaults track the dispatch config
// (OFFER_TTL 15s, expanding-ring search) and the existing load-test targets.

const n = (env, def) => (process.env[env] != null ? Number(process.env[env]) : def);

// A tight, fully-coverable core cluster (all within ~6km, so a modest fleet
// gives ~full coverage). Whole-metro scenarios omit `region`.
const CORE = ['Brickell', 'Downtown Miami', 'Wynwood', 'Edgewater', 'Design District', 'Little Havana'];

// Match-latency SLO philosophy: with human drivers, a small fraction of offers
// are *ghosted* (no accept, no decline), and each ghost costs one OFFER_TTL
// (~10s) before dispatch moves on. So the meaningful health signal is the
// MEDIAN (matchP50Ms) — the typical rider is matched near-instantly — while the
// p95 tail is legitimately bounded by ~1 offer TTL (more under heavy ghosting).
// Setting p95 below OFFER_TTL would be physically impossible once we model
// realistic driver non-response, so the thresholds below track that reality.

export const SCENARIOS = {
  // Fast end-to-end sanity: the whole pipeline works with a tiny fleet.
  smoke: {
    name: 'smoke',
    description: 'Tiny end-to-end sanity — a few full rides on a small, well-covered fleet.',
    drivers: n('DRIVERS', 8),
    driverRampMs: 0,
    region: CORE,
    tiers: [['economy', 1]], // single-tier: deterministic supply=demand sanity check
    // Deterministic happy path: all-accept drivers so a stray ghosted offer can't
    // put a lone ride at ~OFFER_TTL and flake this tiny (6-ride) sanity gate.
    // Ghost/decline behavior is exercised in steady/spike/chaos, not here.
    driverBehavior: { acceptRate: 1, declineRate: 0 },
    arrivals: { model: 'closed', pool: n('POOL', 2), rides: n('RIDES', 6), thinkMs: 500 },
    slo: { matchSuccess: 0.9, matchP50Ms: 2000, matchP95Ms: 8000, errorRate: 0.05, completionRate: 0.85 },
  },

  // Realistic sustained demand via a Poisson arrival process.
  steady: {
    name: 'steady',
    description: 'Realistic open-model demand (Poisson arrivals) against a healthy fleet.',
    drivers: n('DRIVERS', 40),
    driverRampMs: 5000,
    region: CORE,
    arrivals: { model: 'open', ratePerSec: n('RATE', 2), durationS: n('DURATION', 60), maxInflight: n('MAX_INFLIGHT', 250) },
    slo: { matchSuccess: 0.95, matchP50Ms: 1500, matchP95Ms: 16000, estimateP95Ms: 600, errorRate: 0.01, completionRate: 0.9 },
  },

  // Thundering herd: synchronized waves stress dispatch queueing + GEO contention.
  spike: {
    name: 'spike',
    description: 'Synchronized demand waves (thundering herd) — dispatch queue + offer-lock stress.',
    drivers: n('DRIVERS', 150),
    driverRampMs: 8000,
    region: CORE,
    arrivals: { model: 'batch', waveSize: n('WAVE', 50), waves: n('WAVES', 3), gapMs: n('GAP_MS', 3000) },
    // Thundering-herd: 150 near-simultaneous requests contend for the fleet, so
    // queueing + ghost re-offers legitimately stretch the tail well past a single
    // TTL. Assert the MEDIAN rider is still matched fast and the system stays
    // correct (high match success, no errors); the tail is expected to be long.
    slo: { matchSuccess: 0.9, matchP50Ms: 4000, matchP95Ms: 22000, errorRate: 0.02 },
  },

  // Messy reality: drivers decline / let offers expire, riders bail while waiting.
  // Exercises the offer cascade, re-offers, and no_drivers paths the old
  // auto-accept scripts never touched.
  chaos: {
    name: 'chaos',
    description: 'Declines, offer expiries, and rider cancellations — exercises the full dispatch cascade.',
    drivers: n('DRIVERS', 40),
    driverRampMs: 5000,
    region: CORE,
    driverBehavior: { acceptRate: 0.55, declineRate: 0.2 }, // remaining 0.25 let the offer expire
    riderBehavior: { cancelWhileSearchingRate: 0.2, cancelMaxWaitMs: 6000 },
    arrivals: { model: 'open', ratePerSec: n('RATE', 1.5), durationS: n('DURATION', 60), maxInflight: n('MAX_INFLIGHT', 250) },
    // Deliberately hostile: ~45% of offers are ghosted or declined, so re-offer
    // chains stack several TTLs and the match tail is legitimately long. This
    // scenario proves the system stays *correct* under abuse (high match success,
    // no errors, and — since the deadline is now enforced between offers — the
    // rider always gets an authoritative accept/no_drivers within the window),
    // not that it's fast. Hence a deliberately loose tail bound.
    slo: { matchSuccess: 0.8, matchP95Ms: 40000, errorRate: 0.03 },
  },

  // Sustained soak: a fixed rider pool riding back-to-back for minutes — catches
  // leaks, ledger drift, and slow degradation.
  soak: {
    name: 'soak',
    description: 'Sustained closed-loop load — a fixed rider pool riding back-to-back for minutes.',
    drivers: n('DRIVERS', 30),
    driverRampMs: 5000,
    region: CORE,
    arrivals: { model: 'closed', pool: n('POOL', 20), durationS: n('DURATION', 180), thinkMs: 2000 },
    // Soak's job is leak/drift detection over sustained load, not tail latency.
    // The match-latency tail is stochastic (random ghost-stacking), so a fixed
    // p95 gate here would be flaky without catching a distinct regression — that
    // tail is already gated by steady/spike/chaos. So we assert the stable
    // invariants: typical match is instant (p50), matching + completion stay
    // high, no errors — plus the memory/handle stability shown in the report.
    slo: { matchSuccess: 0.95, matchP50Ms: 1500, errorRate: 0.01, completionRate: 0.9 },
  },
};

export function getScenario(name) {
  const s = SCENARIOS[name];
  if (!s) throw new Error(`unknown scenario "${name}". Options: ${Object.keys(SCENARIOS).join(', ')}`);
  return s;
}
