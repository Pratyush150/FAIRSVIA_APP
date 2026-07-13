import { Injectable } from '@nestjs/common';
import {
  Registry,
  collectDefaultMetrics,
  Counter,
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
