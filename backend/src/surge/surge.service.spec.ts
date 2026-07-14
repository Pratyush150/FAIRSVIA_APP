import { SurgeService, SURGE_CAP } from './surge.service';
import { RedisService } from '../common/redis/redis.service';

/** Minimal fake Redis: `get` keyed by substring, `geosearch` by tier. */
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
        if (k.includes('demand')) return demand ? String(demand) : null;
        return null;
      },
      // All supply attributed to the first tier pool; others empty.
      geosearch: async (key: string) =>
        key.endsWith('economy') ? new Array(supply).fill('d') : [],
    },
  } as unknown as RedisService;
}

describe('SurgeService', () => {
  const mult = (o: Parameters<typeof makeRedis>[0]) =>
    new SurgeService(makeRedis(o)).multiplierFor(12.9, 77.6);

  it('is 1.0 with no demand', async () => {
    expect(await mult({ demand: 0, supply: 5 })).toBe(1);
  });

  it('caps when there is demand but zero supply', async () => {
    expect(await mult({ demand: 3, supply: 0 })).toBe(SURGE_CAP);
  });

  it('steps up with the demand:supply ratio', async () => {
    expect(await mult({ demand: 6, supply: 2 })).toBe(SURGE_CAP); // ratio 3
    expect(await mult({ demand: 4, supply: 2 })).toBe(1.5); // ratio 2
    expect(await mult({ demand: 3, supply: 2 })).toBe(1.3); // ratio 1.5
    expect(await mult({ demand: 2, supply: 2 })).toBe(1.2); // ratio 1
    expect(await mult({ demand: 1, supply: 3 })).toBe(1); // ratio 0.33
  });

  it('honours an admin override as a floor', async () => {
    // Low organic demand, but an override forces 1.5.
    expect(await mult({ demand: 0, supply: 9, override: 1.5 })).toBe(1.5);
  });

  it('lets organic surge exceed a lower override', async () => {
    expect(await mult({ demand: 3, supply: 0, override: 1.2 })).toBe(SURGE_CAP);
  });
});
