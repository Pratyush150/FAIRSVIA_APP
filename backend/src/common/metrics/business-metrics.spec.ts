import { MetricsService } from './metrics.service';
import { BusinessMetricsService } from './business-metrics.service';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';

function build(opts: {
  statusKeys?: string[];
  statusValues?: (string | null)[];
  tierValues?: (string | null)[];
  activeTrips?: number;
  queueCounts?: Record<string, number>;
  failRedis?: boolean;
  /** Driver ids whose last location ping is old (a ghost left online). */
  staleIds?: string[];
}) {
  const metrics = new MetricsService();
  const prisma = {
    trip: { count: jest.fn().mockResolvedValue(opts.activeTrips ?? 0) },
  } as unknown as PrismaService;

  const keys = jest.fn().mockResolvedValue(opts.statusKeys ?? []);
  const mget = jest
    .fn()
    .mockResolvedValueOnce(opts.statusValues ?? [])
    .mockResolvedValueOnce(opts.tierValues ?? []);
  // Location pings: fresh for everyone except staleIds.
  const pipeline = () => {
    const ids: string[] = [];
    const p = {
      hget: (key: string) => {
        ids.push(key.split(':')[1]);
        return p;
      },
      exec: async () =>
        ids.map((id) => [null, (opts.staleIds ?? []).includes(id) ? String(Date.now() - 3600_000) : String(Date.now())]),
    };
    return p;
  };
  const redis = {
    client: opts.failRedis
      ? { keys: jest.fn().mockRejectedValue(new Error('redis down')), mget, pipeline }
      : { keys, mget, pipeline },
  } as unknown as RedisService;

  const counts = opts.queueCounts ?? { waiting: 0, active: 0 };
  const queue = { getJobCounts: jest.fn().mockResolvedValue(counts) };
  const service = new BusinessMetricsService(
    metrics,
    prisma,
    redis,
    { localConnectionsByRole: () => new Map([['rider', 2]]) } as never,
    queue as never,
    queue as never,
  );
  service.onModuleInit();
  return { metrics, service, prisma, queue };
}

/** Pull one sample out of the registry, by metric and label match. */
async function sample(
  metrics: MetricsService,
  name: string,
  labels: Record<string, string> = {},
): Promise<number | undefined> {
  const json = await metrics.registry.getMetricsAsJSON();
  const metric = json.find((m) => m.name === name);
  const values = (metric?.values ?? []) as {
    value: number;
    labels: Record<string, string>;
  }[];
  const hit = values.find((v) =>
    Object.entries(labels).every(([k, val]) => v.labels[k] === val),
  );
  return hit?.value;
}

describe('BusinessMetricsService', () => {
  it('fills the gauges only when Prometheus actually scrapes', async () => {
    // Scrape-time collection, not a background timer: nothing should have run
    // just because the service started.
    const { prisma } = build({ activeTrips: 7 });
    expect((prisma.trip.count as jest.Mock)).not.toHaveBeenCalled();
  });

  it('reports active trips at scrape time', async () => {
    const { metrics, prisma } = build({ activeTrips: 7 });
    expect(await sample(metrics, 'active_trips')).toBe(7);
    expect(prisma.trip.count).toHaveBeenCalled();
  });

  it('reports queue depth per queue and state', async () => {
    const { metrics } = build({
      queueCounts: { waiting: 42, active: 3, failed: 1 },
    });
    expect(
      await sample(metrics, 'dispatch_queue_depth', {
        queue: 'dispatch',
        state: 'waiting',
      }),
    ).toBe(42);
    expect(
      await sample(metrics, 'dispatch_queue_depth', {
        queue: 'notifications',
        state: 'failed',
      }),
    ).toBe(1);
  });

  it('counts online drivers per tier, including those on a trip', async () => {
    const { metrics } = build({
      statusKeys: ['driver:a:status', 'driver:b:status', 'driver:c:status'],
      // `on_trip` is still online supply, even though dispatch has taken them
      // out of the matching pool.
      statusValues: ['online', 'on_trip', 'offline'],
      tierValues: ['economy', 'economy'],
    });
    expect(await sample(metrics, 'drivers_online', { tier: 'economy' })).toBe(2);
  });

  it('counts busy drivers once, even though two gauges ask for them', async () => {
    const { metrics } = build({
      statusKeys: ['driver:a:status', 'driver:b:status', 'driver:c:status'],
      statusValues: ['online', 'on_trip', 'on_trip'],
      tierValues: ['economy', 'xl', 'xl'],
    });
    expect(await sample(metrics, 'drivers_on_trip')).toBe(2);
    expect(await sample(metrics, 'drivers_online', { tier: 'xl' })).toBe(2);
    // The build() mock answers exactly one status read + one tier read; a
    // second Redis read per scrape would have returned nothing and zeroed a
    // gauge. Both gauges above being right is the proof they shared one.
  });

  it("doesn't count a driver whose phone stopped sending positions", async () => {
    // Driver c's status still says on_trip, but its last ping is an hour old.
    const { metrics } = build({
      statusKeys: ['driver:a:status', 'driver:b:status', 'driver:c:status'],
      statusValues: ['online', 'on_trip', 'on_trip'],
      tierValues: ['economy', 'economy'],
      staleIds: ['c'],
    });
    expect(await sample(metrics, 'drivers_online', { tier: 'economy' })).toBe(2);
    expect(await sample(metrics, 'drivers_on_trip')).toBe(1);
  });

  it('reports WebSocket connections by role, with 0 rather than a gap', async () => {
    const { metrics } = build({});
    expect(await sample(metrics, 'websocket_connections', { role: 'rider' })).toBe(2);
    expect(await sample(metrics, 'websocket_connections', { role: 'driver' })).toBe(0);
  });

  it('buckets an online driver with no tier rather than dropping them', async () => {
    const { metrics } = build({
      statusKeys: ['driver:a:status'],
      statusValues: ['online'],
      tierValues: [null],
    });
    // Dropping them would make the gauge disagree with the live ops view.
    expect(await sample(metrics, 'drivers_online', { tier: 'unknown' })).toBe(1);
  });

  it('loses one gauge, not the whole scrape, when a query fails', async () => {
    // A failing collector must not take down /metrics — losing drivers_online
    // is far better than losing every metric plus the default process ones.
    const { metrics } = build({ failRedis: true, activeTrips: 4 });
    const json = await metrics.registry.getMetricsAsJSON();
    expect(json.find((m) => m.name === 'process_cpu_user_seconds_total')).toBeDefined();
    expect(await sample(metrics, 'active_trips')).toBe(4);
  });
});

describe('MetricsService business counters', () => {
  /** The value of one line of Prometheus exposition text. */
  function textValue(text: string, line: string): number | undefined {
    const match = text
      .split('\n')
      .find((l) => l.startsWith(line) && !l.startsWith('#'));
    return match ? Number(match.slice(match.lastIndexOf(' ') + 1)) : undefined;
  }

  it('ignores an impossible match duration rather than poisoning the SLO', async () => {
    const metrics = new MetricsService();
    metrics.observeMatch(-5); // clock skew, not a fast match
    metrics.observeMatch(Number.NaN);
    metrics.observeMatch(2);

    const text = await metrics.scrape();
    expect(textValue(text, 'trip_match_duration_seconds_count')).toBe(1);
    expect(textValue(text, 'trip_match_duration_seconds_sum')).toBe(2);
  });

  it('labels vendor calls by outcome, so a quota wall is visible', async () => {
    const metrics = new MetricsService();
    metrics.observeVendor('google', 'route', true, 120);
    metrics.observeVendor('google', 'route', false, 3000);
    metrics.observeVendor('osm', 'route', true, 40);

    const text = await metrics.scrape();
    expect(
      textValue(
        text,
        'vendor_request_duration_seconds_count{vendor="google",operation="route",status="error"}',
      ),
    ).toBe(1);
    expect(
      textValue(
        text,
        'vendor_request_duration_seconds_count{vendor="osm",operation="route",status="ok"}',
      ),
    ).toBe(1);
  });

  it('counts the trip funnel by status', async () => {
    const metrics = new MetricsService();
    metrics.tripStatus('matching');
    metrics.tripStatus('accepted');
    metrics.tripStatus('accepted');

    const text = await metrics.scrape();
    expect(textValue(text, 'trips_total{status="accepted"}')).toBe(2);
    expect(textValue(text, 'trips_total{status="matching"}')).toBe(1);
  });

  it('counts offer outcomes, and every outcome exists from boot at 0', async () => {
    const metrics = new MetricsService();
    let text = await metrics.scrape();
    for (const outcome of ['accepted', 'declined', 'expired']) {
      expect(textValue(text, `dispatch_offers_total{outcome="${outcome}"}`)).toBe(0);
    }
    metrics.offerOutcome('accepted');
    metrics.offerOutcome('expired');
    metrics.offerOutcome('expired');
    text = await metrics.scrape();
    expect(textValue(text, 'dispatch_offers_total{outcome="accepted"}')).toBe(1);
    expect(textValue(text, 'dispatch_offers_total{outcome="expired"}')).toBe(2);
  });

  it('separates a retried payment failure from an exhausted one', async () => {
    // A burst that eventually succeeds is a vendor blip; a rising `exhausted`
    // line is money that never arrived.
    const metrics = new MetricsService();
    metrics.paymentFailed('capture', 'retrying');
    metrics.paymentFailed('capture', 'exhausted');

    const text = await metrics.scrape();
    expect(
      textValue(text, 'payment_failures_total{kind="capture",reason="exhausted"}'),
    ).toBe(1);
  });
});
