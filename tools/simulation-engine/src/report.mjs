// Turns a raw Metrics snapshot into a verdict: derived rates, SLO pass/fail, a
// pitfall taxonomy, and a best-effort scrape of the backend's Prometheus metrics
// so client-side symptoms can be correlated with server-side state.

import { METRICS_URL } from './config.mjs';

export async function buildReport(scenario, metrics) {
  const snap = metrics.snapshot();
  const c = snap.counters;
  const requested = c['rides.requested'] || 0;

  const derived = {
    requested,
    matched: c['matches.success'] || 0,
    completed: c['rides.completed'] || 0,
    noDrivers: c['matches.no_drivers'] || 0,
    matchTimeout: c['matches.timeout'] || 0,
    cancelledSearching: c['rides.cancelled_searching'] || 0,
    offersReceived: c['offers.received'] || 0,
    offersDeclined: c['offers.declined'] || 0,
    offersExpired: c['offers.expired_by_driver'] || 0,
    offersAcceptLost: c['offers.accept_lost'] || 0,
    wsDisconnects: (c['ws.rider.disconnects'] || 0) + (c['ws.driver.disconnects'] || 0),
    errors: snap.failures.byKind.error || 0,
  };
  derived.matchSuccessRate = requested ? derived.matched / requested : 0;
  derived.completionRate = requested ? derived.completed / requested : 0;
  derived.errorRate = requested ? derived.errors / requested : 0;
  derived.throughputPerMin = snap.durationMs ? (derived.completed / (snap.durationMs / 60000)) : 0;

  const t = snap.timers;
  const slo = scenario.slo || {};
  const checks = [];
  const check = (name, ok, actual, target) => checks.push({ name, ok, actual, target });

  if (slo.matchSuccess != null)
    check('match success rate', derived.matchSuccessRate >= slo.matchSuccess, fmtPct(derived.matchSuccessRate), `>= ${fmtPct(slo.matchSuccess)}`);
  if (slo.matchP50Ms != null)
    check('match latency p50', (t['match.ms']?.p50 ?? 0) <= slo.matchP50Ms, `${t['match.ms']?.p50 ?? 0}ms`, `<= ${slo.matchP50Ms}ms`);
  if (slo.matchP95Ms != null)
    check('match latency p95', (t['match.ms']?.p95 ?? 0) <= slo.matchP95Ms, `${t['match.ms']?.p95 ?? 0}ms`, `<= ${slo.matchP95Ms}ms`);
  if (slo.e2eP95Ms != null && t['ride.e2e.ms'])
    check('ride e2e p95', t['ride.e2e.ms'].p95 <= slo.e2eP95Ms, `${t['ride.e2e.ms'].p95}ms`, `<= ${slo.e2eP95Ms}ms`);
  if (slo.estimateP95Ms != null && t['estimate.ms'])
    check('estimate p95', t['estimate.ms'].p95 <= slo.estimateP95Ms, `${t['estimate.ms'].p95}ms`, `<= ${slo.estimateP95Ms}ms`);
  if (slo.errorRate != null)
    check('error rate', derived.errorRate <= slo.errorRate, fmtPct(derived.errorRate), `<= ${fmtPct(slo.errorRate)}`);
  if (slo.completionRate != null)
    check('completion rate', derived.completionRate >= slo.completionRate, fmtPct(derived.completionRate), `>= ${fmtPct(slo.completionRate)}`);

  const passed = checks.every((c) => c.ok);
  const server = await scrapeServer();

  return { scenario: scenario.name, description: scenario.description, snap, derived, checks, passed, server };
}

export function printReport(r) {
  const line = '─'.repeat(64);
  console.log(`\n${line}\n  SIMULATION REPORT — ${r.scenario}\n  ${r.description}\n${line}`);
  console.log(`  duration: ${(r.snap.durationMs / 1000).toFixed(1)}s`);

  console.log('\n  Demand & matching');
  row('requested', r.derived.requested);
  row('matched', `${r.derived.matched}  (${fmtPct(r.derived.matchSuccessRate)})`);
  row('completed', `${r.derived.completed}  (${fmtPct(r.derived.completionRate)})`);
  row('no drivers', r.derived.noDrivers);
  row('match timeouts', r.derived.matchTimeout);
  row('cancelled (searching)', r.derived.cancelledSearching);
  row('throughput', `${r.derived.throughputPerMin.toFixed(1)} rides/min`);

  console.log('\n  Offer cascade');
  row('offers received', r.derived.offersReceived);
  row('declined', r.derived.offersDeclined);
  row('let expire', r.derived.offersExpired);
  row('accept lost (race)', r.derived.offersAcceptLost);

  console.log('\n  Latency (ms)');
  for (const [name, key] of [['estimate', 'estimate.ms'], ['create trip', 'createTrip.ms'], ['match', 'match.ms'], ['ride e2e', 'ride.e2e.ms']]) {
    const s = r.snap.timers[key];
    if (s && s.count) console.log(`    ${name.padEnd(14)} n=${String(s.count).padEnd(5)} avg=${s.avg.toFixed(0)} p50=${s.p50} p95=${s.p95} p99=${s.p99} max=${s.max}`);
  }

  console.log('\n  Pitfalls & failures');
  row('total failures', r.snap.failures.total);
  row('ws disconnects', r.derived.wsDisconnects);
  const kinds = r.snap.failures.byKind;
  for (const k of Object.keys(kinds)) console.log(`    ${('· ' + k).padEnd(24)} ${kinds[k]}`);
  if (r.snap.failures.sample.length) {
    console.log('\n  Failure samples (first few):');
    for (const f of r.snap.failures.sample.slice(0, 8)) {
      console.log(`    [${(f.tMs / 1000).toFixed(1)}s] ${f.kind} ${f.actor || ''}/${f.op || ''}${f.status ? ' ' + f.status : ''}: ${f.detail}`);
    }
  }

  if (r.server && r.server.ok) {
    console.log('\n  Server (Prometheus scrape at end)');
    for (const [k, v] of Object.entries(r.server.metrics)) console.log(`    ${k.padEnd(30)} ${v}`);
  } else if (r.server) {
    console.log(`\n  Server metrics scrape: unavailable (${r.server.error})`);
  }

  console.log(`\n${line}`);
  console.log('  SLO checks');
  for (const c of r.checks) console.log(`    ${c.ok ? '✓' : '✗'} ${c.name.padEnd(22)} ${String(c.actual).padEnd(12)} (target ${c.target})`);
  console.log(`${line}`);
  console.log(`  VERDICT: ${r.passed ? 'PASS ✓' : 'FAIL ✗'}\n${line}\n`);
}

async function scrapeServer() {
  try {
    const res = await fetch(METRICS_URL, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) return { ok: false, error: `HTTP ${res.status}` };
    const text = await res.text();
    const wanted = ['nodejs_eventloop_lag_p99_seconds', 'process_resident_memory_bytes', 'nodejs_active_handles_total'];
    const metrics = {};
    for (const line of text.split('\n')) {
      if (line.startsWith('#') || !line.trim()) continue;
      const [name, val] = line.split(/\s+/);
      const base = name.split('{')[0];
      if (wanted.includes(base) && metrics[base] == null) metrics[base] = val;
      // Capture any bull/queue/dispatch/trip gauges heuristically.
      if (/queue|dispatch|trip/i.test(base) && Object.keys(metrics).length < 24) {
        metrics[name.length > 40 ? base : name] = val;
      }
    }
    return { ok: true, metrics };
  } catch (e) {
    return { ok: false, error: e.message };
  }
}

function row(label, val) {
  console.log(`    ${String(label).padEnd(24)} ${val}`);
}
function fmtPct(x) {
  return `${(x * 100).toFixed(1)}%`;
}
