// Central metrics + failure collector. Every actor reports into one instance so
// results are aggregated across the whole run (vs. per-script printouts). Also
// captures a structured failure log — the "pitfalls" surface the engine exists
// to expose.

export class Metrics {
  constructor() {
    this.timers = new Map(); // name -> number[] (ms)
    this.counters = new Map(); // name -> number
    this.failures = []; // { t, kind, actor, op, detail, status }
    this.startedAt = Date.now();
  }

  timer(name, ms) {
    if (!this.timers.has(name)) this.timers.set(name, []);
    this.timers.get(name).push(ms);
  }

  incr(name, n = 1) {
    this.counters.set(name, (this.counters.get(name) || 0) + n);
  }

  count(name) {
    return this.counters.get(name) || 0;
  }

  /** Record a structured failure/anomaly with as much context as available. */
  fail(kind, { actor, op, detail, status } = {}) {
    this.failures.push({
      tMs: Date.now() - this.startedAt,
      kind,
      actor,
      op,
      detail: typeof detail === 'string' ? detail : detail?.message || String(detail || ''),
      status,
    });
  }

  /** Convenience: record an exception thrown by an actor operation. */
  error(actor, op, err) {
    this.fail('error', {
      actor,
      op,
      detail: err?.message || String(err),
      status: err?.status,
    });
  }

  stats(name) {
    const s = [...(this.timers.get(name) || [])].sort((a, b) => a - b);
    if (s.length === 0) return { count: 0, avg: 0, p50: 0, p95: 0, p99: 0, max: 0 };
    const sum = s.reduce((a, b) => a + b, 0);
    return {
      count: s.length,
      avg: sum / s.length,
      p50: pct(s, 50),
      p95: pct(s, 95),
      p99: pct(s, 99),
      max: s[s.length - 1],
    };
  }

  /** A serializable snapshot of everything collected so far. */
  snapshot() {
    const timers = {};
    for (const name of this.timers.keys()) timers[name] = this.stats(name);
    const counters = Object.fromEntries(this.counters);
    // Group failures by kind for a quick taxonomy.
    const byKind = {};
    for (const f of this.failures) byKind[f.kind] = (byKind[f.kind] || 0) + 1;
    return {
      durationMs: Date.now() - this.startedAt,
      timers,
      counters,
      failures: { total: this.failures.length, byKind, sample: this.failures.slice(0, 40) },
    };
  }
}

function pct(sortedAsc, p) {
  if (sortedAsc.length === 0) return 0;
  const idx = Math.min(sortedAsc.length - 1, Math.ceil((p / 100) * sortedAsc.length) - 1);
  return sortedAsc[Math.max(0, idx)];
}
