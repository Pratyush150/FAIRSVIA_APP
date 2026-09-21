import { Injectable } from '@nestjs/common';
import {
  Registry,
  collectDefaultMetrics,
  Counter,
  Gauge,
  Histogram,
} from 'prom-client';

/**
 * Owns the Prometheus registry and the HTTP request metrics. Also keeps a few
 * cheap running totals so the admin dashboard can show a friendly snapshot
 * without parsing the Prometheus exposition format.
 */
@Injectable()
export class MetricsService {
  readonly registry = new Registry();

  private readonly httpTotal: Counter<string>;
  private readonly httpDuration: Histogram<string>;

  // --- Business metrics ------------------------------------------------------
  // HTTP throughput tells you the server is up. These tell you the marketplace
  // is working, which is a different question and the one that matters.

  /**
   * Trips entering each status. The funnel — requested → matching → accepted →
   * completed — read as rates rather than totals, so a collapse in matching
   * shows up as a gap between two lines instead of needing a query.
   */
  private readonly tripsTotal: Counter<string>;

  /**
   * Seconds from a trip being requested to a driver accepting it. This is the
   * 4s SLO, measured live instead of inferred from a load test. Buckets are
   * placed around the measured p95 (2.46s at the 300-ride ceiling) so the
   * histogram has resolution exactly where the alert threshold sits.
   */
  private readonly matchDuration: Histogram<string>;

  /** Payment failures by kind and reason — directly revenue-impacting. */
  private readonly paymentFailures: Counter<string>;

  /**
   * Outbound vendor calls (Google, OSRM, Nominatim, Stripe, SES, SMS). The
   * 20,370 Google OVER_QUERY_LIMIT errors in the load sweep were invisible for
   * hours; this makes that failure mode a line on a graph.
   */
  private readonly vendorDuration: Histogram<string>;

  /** Gauges filled at scrape time — see [setCollector]. */
  readonly dispatchQueueDepth: Gauge<string>;
  readonly driversOnline: Gauge<string>;
  readonly activeTrips: Gauge<string>;

  /**
   * Scrape-time fillers for the gauges above, keyed by gauge name.
   *
   * The gauges live here (so `/metrics` owns its registry) but the data they
   * need lives behind Prisma, Redis and BullMQ, which this service must not
   * depend on. `BusinessMetricsService` registers the callbacks instead.
   */
  private readonly collectors = new Map<string, () => Promise<void>>();

  // Lightweight cumulative counters (since boot) for the JSON snapshot.
  private reqCount = 0;
  private errCount = 0;
  private durSumMs = 0;

  constructor() {
    collectDefaultMetrics({ register: this.registry });
    this.httpTotal = new Counter({
      name: 'http_requests_total',
      help: 'Total HTTP requests',
      labelNames: ['method', 'route', 'status'],
      registers: [this.registry],
    });
    this.httpDuration = new Histogram({
      name: 'http_request_duration_seconds',
      help: 'HTTP request duration in seconds',
      labelNames: ['method', 'route', 'status'],
      buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
      registers: [this.registry],
    });

    this.tripsTotal = new Counter({
      name: 'trips_total',
      help: 'Trips entering each status',
      labelNames: ['status'],
      registers: [this.registry],
    });
    this.matchDuration = new Histogram({
      name: 'trip_match_duration_seconds',
      help: 'Seconds from trip requested to driver accepted',
      // Dense around the 2.5s alert threshold; the long tail only needs to
      // say "this was bad", not how bad.
      buckets: [0.5, 1, 2, 2.5, 3, 4, 5, 7.5, 10, 20, 60],
      registers: [this.registry],
    });
    this.paymentFailures = new Counter({
      name: 'payment_failures_total',
      help: 'Payment operations that failed',
      labelNames: ['kind', 'reason'],
      registers: [this.registry],
    });
    this.vendorDuration = new Histogram({
      name: 'vendor_request_duration_seconds',
      help: 'Outbound third-party request duration',
      labelNames: ['vendor', 'operation', 'status'],
      buckets: [0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10],
      registers: [this.registry],
    });

    // Gauges are point-in-time facts, so they are set by a collector at scrape
    // time rather than incremented from call sites.
    this.dispatchQueueDepth = new Gauge({
      name: 'dispatch_queue_depth',
      help: 'Jobs in the dispatch queue, by state',
      labelNames: ['queue', 'state'],
      registers: [this.registry],
      collect: () => this.runCollector('dispatch_queue_depth'),
    });
    this.driversOnline = new Gauge({
      name: 'drivers_online',
      help: 'Drivers currently online, by tier',
      labelNames: ['tier'],
      registers: [this.registry],
      collect: () => this.runCollector('drivers_online'),
    });
    this.activeTrips = new Gauge({
      name: 'active_trips',
      help: 'Trips currently in flight (requested through in_progress)',
      registers: [this.registry],
      collect: () => this.runCollector('active_trips'),
    });
  }

  /**
   * Register the callback that fills the gauge called [gauge] at scrape time.
   * Called once, at startup, by [BusinessMetricsService].
   */
  setCollector(gauge: string, fn: () => Promise<void>): void {
    this.collectors.set(gauge, fn);
  }

  private runCollector(gauge: string): Promise<void> {
    return this.collectors.get(gauge)?.() ?? Promise.resolve();
  }

  /** A trip entered [status]. */
  tripStatus(status: string): void {
    this.tripsTotal.inc({ status });
  }

  /** A driver accepted [seconds] after the trip was requested. */
  observeMatch(seconds: number): void {
    // A negative or absurd duration means clock skew, not a fast match.
    if (!Number.isFinite(seconds) || seconds < 0) return;
    this.matchDuration.observe(seconds);
  }

  /** A payment operation failed. [reason] must be low-cardinality. */
  paymentFailed(kind: string, reason: string): void {
    this.paymentFailures.inc({ kind, reason });
  }

  /** Record one outbound vendor call. */
  observeVendor(
    vendor: string,
    operation: string,
    ok: boolean,
    durationMs: number,
  ): void {
    this.vendorDuration.observe(
      { vendor, operation, status: ok ? 'ok' : 'error' },
      durationMs / 1000,
    );
  }

  /** Record a completed request. */
  observe(method: string, route: string, status: number, durationMs: number) {
    const labels = { method, route, status: String(status) };
    this.httpTotal.inc(labels);
    this.httpDuration.observe(labels, durationMs / 1000);
    this.reqCount += 1;
    this.durSumMs += durationMs;
    if (status >= 500) this.errCount += 1;
  }

  /** Friendly rollup for the dashboard. */
  snapshot() {
    return {
      requestsTotal: this.reqCount,
      errorsTotal: this.errCount,
      errorRate: this.reqCount ? this.errCount / this.reqCount : 0,
      avgLatencyMs: this.reqCount ? Math.round(this.durSumMs / this.reqCount) : 0,
    };
  }

  /** Prometheus exposition text for `GET /metrics`. */
  scrape(): Promise<string> {
    return this.registry.metrics();
  }
}
