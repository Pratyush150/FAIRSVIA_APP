import { MetricsService } from './metrics.service';

describe('MetricsService', () => {
  it('accumulates request totals, 5xx errors, and average latency', () => {
    const m = new MetricsService();
    m.observe('GET', '/x', 200, 10);
    m.observe('GET', '/x', 200, 30);
    m.observe('POST', '/y', 500, 20); // a server error

    const s = m.snapshot();
    expect(s.requestsTotal).toBe(3);
    expect(s.errorsTotal).toBe(1);
    expect(s.avgLatencyMs).toBe(20); // (10 + 30 + 20) / 3
    expect(s.errorRate).toBeCloseTo(1 / 3);
  });

  it('treats 4xx as non-errors for the error rate', () => {
    const m = new MetricsService();
    m.observe('GET', '/x', 404, 5);
    expect(m.snapshot().errorsTotal).toBe(0);
  });

  it('exposes prometheus exposition text with http metrics', async () => {
    const m = new MetricsService();
    m.observe('GET', '/x', 200, 5);
    const text = await m.scrape();
    expect(text).toContain('http_requests_total');
    expect(text).toContain('http_request_duration_seconds');
  });
});
