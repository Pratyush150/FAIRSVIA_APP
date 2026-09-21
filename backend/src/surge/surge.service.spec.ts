import { DEMAND_TTL, SurgeService, SURGE_CAP } from './surge.service';
import { RedisService } from '../common/redis/redis.service';

/** Every kill switch off, i.e. normal operation. */
const flagsAllOff = { isOn: jest.fn().mockResolvedValue(false) };

/** Minimal fake Redis: demand is a SET per cell (scard), `geosearch` by tier. */
function makeRedis(opts: {
  demand?: number;
  override?: number;
  supply?: number;
}) {
  const demand = opts.demand ?? 0;
  const override = opts.override ?? 1;
  const supply = opts.supply ?? 0;
  return {
    client: {
      get: async (k: string) => {
        if (k.includes('override')) return override > 1 ? String(override) : null;
        return null;
      },
      scard: async (k: string) => (k.includes('demand') ? demand : 0),
      // All supply attributed to the first tier pool; others empty.
      geosearch: async (key: string) =>
        key.endsWith('economy') ? new Array(supply).fill('d') : [],
    },
  } as unknown as RedisService;
}

/** Real set semantics so rider de-duplication is exercised, not mocked. */
function makeSetRedis() {
  const sets = new Map<string, Set<string>>();
  const expire = jest.fn().mockResolvedValue(1);
  const client = {
    sadd: jest.fn(async (k: string, m: string) => {
      const s = sets.get(k) ?? new Set<string>();
      const added = s.has(m) ? 0 : 1;
      s.add(m);
      sets.set(k, s);
      return added;
    }),
    srem: jest.fn(async (k: string, m: string) => (sets.get(k)?.delete(m) ? 1 : 0)),
    scard: jest.fn(async (k: string) => sets.get(k)?.size ?? 0),
    expire,
    get: jest.fn().mockResolvedValue(null),
    // One online driver, in the economy pool only.
    geosearch: jest.fn(async (key: string) => (key.endsWith('economy') ? ['d1'] : [])),
  };
  return { redis: { client } as unknown as RedisService, client, sets };
}

describe('SurgeService', () => {
  const mult = (o: Parameters<typeof makeRedis>[0]) =>
    new SurgeService(makeRedis(o), flagsAllOff as never)
      .multiplierFor(12.9, 77.6);

  it('is 1.0 with no demand', async () => {
    expect(await mult({ demand: 0, supply: 5 })).toBe(1);
  });

  it('does not surge when no driver is reachable (the ride will fail anyway)',
    async () => {
    expect(await mult({ demand: 3, supply: 0 })).toBe(1);
  });

  it('steps up with the demand:supply ratio', async () => {
    expect(await mult({ demand: 6, supply: 2 })).toBe(SURGE_CAP); // ratio 3
    expect(await mult({ demand: 4, supply: 2 })).toBe(1.5); // ratio 2
    expect(await mult({ demand: 3, supply: 2 })).toBe(1.3); // ratio 1.5
    expect(await mult({ demand: 5, supply: 4 })).toBe(1.2); // ratio 1.25
    expect(await mult({ demand: 2, supply: 2 })).toBe(1); // balanced → no surge
    expect(await mult({ demand: 1, supply: 3 })).toBe(1); // ratio 0.33
    // A lone driver anywhere inside the 9 km dispatch range is real supply.
    expect(await mult({ demand: 1, supply: 1 })).toBe(1);
  });

  it('honours an admin override as a floor', async () => {
    // Low organic demand, but an override forces 1.5.
    expect(await mult({ demand: 0, supply: 9, override: 1.5 })).toBe(1.5);
  });

  it('lets organic surge exceed a lower override', async () => {
    expect(await mult({ demand: 3, supply: 0, override: 1.2 })).toBe(1.2);
  });

  // Demand is a per-cell set of riders: a single rider hammering "request"
  // must not be able to surge their own pickup.
  describe('demand accounting', () => {
    it('counts a rider once per cell however many times they retry', async () => {
      const { redis, client } = makeSetRedis();
      const svc = new SurgeService(redis, flagsAllOff as never);
      await svc.recordDemand(12.9, 77.6, 'rider-A');
      await svc.recordDemand(12.9, 77.6, 'rider-A');
      await svc.recordDemand(12.9, 77.6, 'rider-A');
      // demand 1 vs supply 1 → balanced → no surge (and NOT the cap).
      expect(await svc.multiplierFor(12.9, 77.6)).toBe(1);
      expect(client.expire).toHaveBeenCalledWith(expect.stringContaining('surge:demand:'), DEMAND_TTL);
    });

    it('two distinct riders in the same cell both count', async () => {
      const { redis } = makeSetRedis();
      const svc = new SurgeService(redis, flagsAllOff as never);
      await svc.recordDemand(12.9, 77.6, 'rider-A');
      await svc.recordDemand(12.9, 77.6, 'rider-B');
      // demand 2 vs supply 1 → ratio 2 → 1.5x
      expect(await svc.multiplierFor(12.9, 77.6)).toBe(1.5);
    });

    it('releaseDemand withdraws a rider whose request ended without a ride', async () => {
      const { redis } = makeSetRedis();
      const svc = new SurgeService(redis, flagsAllOff as never);
      await svc.recordDemand(12.9, 77.6, 'rider-A');
      await svc.recordDemand(12.9, 77.6, 'rider-B');
      await svc.releaseDemand(12.9, 77.6, 'rider-A');
      // Back to demand 1 vs supply 1 → balanced → no surge.
      expect(await svc.multiplierFor(12.9, 77.6)).toBe(1);
      // Releasing again (or a rider never recorded) is a harmless no-op.
      await expect(svc.releaseDemand(12.9, 77.6, 'rider-A')).resolves.toBeUndefined();
      await expect(svc.releaseDemand(12.9, 77.6, 'rider-Z')).resolves.toBeUndefined();
    });
  });
});
