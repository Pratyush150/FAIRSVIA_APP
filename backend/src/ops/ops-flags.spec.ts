import { OpsFlagsService, OPS_FLAG_NAMES } from './ops-flags.service';
import { RedisService } from '../common/redis/redis.service';

function build(hash: Record<string, string> = {}, opts: { fail?: boolean } = {}) {
  const hgetall = opts.fail
    ? jest.fn().mockRejectedValue(new Error('redis down'))
    : jest.fn().mockResolvedValue(hash);
  const hset = jest.fn().mockResolvedValue(1);
  const redis = { client: { hgetall, hset } } as unknown as RedisService;
  return { service: new OpsFlagsService(redis), hgetall, hset };
}

describe('OpsFlagsService', () => {
  it('reports every switch off when nothing is set', async () => {
    const { service } = build();
    const all = await service.all();
    expect(Object.keys(all).sort()).toEqual([...OPS_FLAG_NAMES].sort());
    expect(Object.values(all).every((v) => v === false)).toBe(true);
  });

  it('reads a flag that has been set', async () => {
    const { service } = build({ dispatchPaused: '1' });
    expect(await service.isOn('dispatchPaused')).toBe(true);
    expect(await service.isOn('surgeDisabled')).toBe(false);
  });

  it('treats anything that is not "1" as off', async () => {
    // A half-written value must not read as "paused".
    const { service } = build({ dispatchPaused: 'true' });
    expect(await service.isOn('dispatchPaused')).toBe(false);
  });

  it('reports all-off rather than throwing when Redis is unreachable', async () => {
    // THE important one: a Redis blip must not be able to pause the
    // marketplace. Reads fail safe, toward normal operation.
    const { service } = build({}, { fail: true });
    await expect(service.all()).resolves.toBeDefined();
    expect(await service.isOn('dispatchPaused')).toBe(false);
  });

  it('does not cache a failed read', async () => {
    const { service, hgetall } = build({}, { fail: true });
    await service.all();
    await service.all();
    // Both went to Redis: a transient failure must not pin "all off" for the
    // whole cache window and hide a switch that is genuinely on.
    expect(hgetall).toHaveBeenCalledTimes(2);
  });

  it('caches a successful read, so the hot path is not a Redis call each time',
    async () => {
      const { service, hgetall } = build({ surgeDisabled: '1' });
      await service.all();
      await service.all();
      await service.isOn('surgeDisabled');
      expect(hgetall).toHaveBeenCalledTimes(1);
    });

  it('a write takes effect immediately, without waiting for the cache', async () => {
    // An operator who flips a switch and sees the old value would flip it
    // again. The write invalidates the cache.
    const { service, hgetall, hset } = build({});
    await service.all(); // warm the cache with everything off
    hgetall.mockResolvedValue({ dispatchPaused: '1' });

    const after = await service.set('dispatchPaused', true);
    expect(hset).toHaveBeenCalledWith('ops:flags', 'dispatchPaused', '1');
    expect(after.dispatchPaused).toBe(true);
  });

  it('surfaces a failed write instead of swallowing it', async () => {
    // Opposite of the read path, deliberately: believing dispatch is paused
    // when it is not is far worse than an error message.
    const { service, hset } = build({});
    hset.mockRejectedValue(new Error('redis down'));
    await expect(service.set('dispatchPaused', true)).rejects.toThrow(
      /redis down/,
    );
  });
});

describe('kill switches at their enforcement points', () => {
  const on = (flag: string) =>
    ({ isOn: jest.fn((f: string) => Promise.resolve(f === flag)) }) as never;

  it('surgeDisabled prices at 1.0x without even reading demand', async () => {
    const { SurgeService } = await import('../surge/surge.service');
    const redis = {
      client: {
        scard: jest.fn(),
        geosearch: jest.fn(),
        get: jest.fn(),
      },
    };
    const svc = new SurgeService(redis as never, on('surgeDisabled'));
    expect(await svc.multiplierFor(25.76, -80.19)).toBe(1);
    // Short-circuited before the demand/supply reads, so throwing the switch
    // also sheds their Redis load.
    expect(redis.client.scard).not.toHaveBeenCalled();
    expect(redis.client.geosearch).not.toHaveBeenCalled();
  });

  it('geoFallbackOnly serves from the secondary without calling the primary',
    async () => {
      const { FallbackGeoProvider } = await import(
        '../geo/fallback-geo.provider'
      );
      const primary = { route: jest.fn() };
      const secondary = {
        route: jest.fn().mockResolvedValue({ distanceM: 1, durationS: 1, polyline: '' }),
      };
      const geo = new FallbackGeoProvider(
        primary as never,
        secondary as never,
        on('geoFallbackOnly'),
      );

      await geo.route({ lat: 0, lng: 0 }, { lat: 1, lng: 1 });
      // Not "tried and failed over" — never called. That is the difference
      // between shedding a quota burn and paying for it twice.
      expect(primary.route).not.toHaveBeenCalled();
      expect(secondary.route).toHaveBeenCalledTimes(1);
    });

  it('with the switch off the primary is still tried first', async () => {
    const { FallbackGeoProvider } = await import('../geo/fallback-geo.provider');
    const primary = {
      route: jest.fn().mockResolvedValue({ distanceM: 2, durationS: 2, polyline: '' }),
    };
    const secondary = { route: jest.fn() };
    const geo = new FallbackGeoProvider(
      primary as never,
      secondary as never,
      { isOn: jest.fn().mockResolvedValue(false) } as never,
    );

    await geo.route({ lat: 0, lng: 0 }, { lat: 1, lng: 1 });
    expect(primary.route).toHaveBeenCalledTimes(1);
    expect(secondary.route).not.toHaveBeenCalled();
  });
});

describe('pausing dispatch defers work rather than losing it', () => {
  const onPaused = { isOn: jest.fn().mockResolvedValue(true) } as never;
  const offPaused = { isOn: jest.fn().mockResolvedValue(false) } as never;

  function makeDispatch(flags: never, trips: Record<string, string> = {}) {
    const sadd = jest.fn().mockResolvedValue(1);
    const smembers = jest.fn().mockResolvedValue(Object.keys(trips));
    const redis = {
      client: {
        sadd,
        smembers,
        del: jest.fn().mockResolvedValue(1),
        scard: jest.fn().mockResolvedValue(Object.keys(trips).length),
      },
    };
    const prisma = {
      trip: {
        findUnique: jest.fn(({ where }: { where: { id: string } }) =>
          Promise.resolve(
            trips[where.id] ? { status: trips[where.id] } : null,
          ),
        ),
      },
    };
    const queue = {
      add: jest.fn().mockResolvedValue({}),
      remove: jest.fn().mockResolvedValue(1),
    };
    return { redis, prisma, queue, sadd, smembers, flags };
  }

  async function service(ctx: ReturnType<typeof makeDispatch>) {
    const { DispatchService } = await import('../dispatch/dispatch.service');
    return new DispatchService(
      ctx.prisma as never,
      ctx.redis as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      ctx.queue as never,
      {} as never,
      {} as never,
      ctx.flags,
      { offerOutcome: jest.fn() } as never,
    );
  }

  it('parks the trip instead of throwing, leaving its status alone', async () => {
    // Throwing looks like deferral but is not: the job has attempts: 3 with a
    // 2s backoff, so any pause over ~6s exhausts the retries and strands the
    // rider in `requested` for ever.
    const ctx = makeDispatch(onPaused, { 't1': 'requested' });
    const svc = await service(ctx);

    await expect(svc.runDispatch('t1')).resolves.toBeUndefined();
    expect(ctx.sadd).toHaveBeenCalledWith('dispatch:deferred', 't1');
    // Never looked the trip up, never transitioned it.
    expect(ctx.prisma.trip.findUnique).not.toHaveBeenCalled();
  });

  it('releases parked trips when the pause is lifted', async () => {
    const ctx = makeDispatch(offPaused, { 't1': 'requested', 't2': 'requested' });
    const svc = await service(ctx);

    expect(await svc.resumeDeferred()).toBe(2);
    expect(ctx.queue.add).toHaveBeenCalledTimes(2);
  });

  it('clears the retained completed job first, or the re-add is discarded',
    async () => {
      // THE bug this test exists for: dispatchTrip de-dupes on jobId: tripId,
      // and BullMQ keeps completed jobs for an hour — so re-adding the same id
      // is silently dropped while the log reports the trip was released.
      const ctx = makeDispatch(offPaused, { 't1': 'requested' });
      const svc = await service(ctx);

      await svc.resumeDeferred();
      expect(ctx.queue.remove).toHaveBeenCalledWith('t1');
      const removeOrder = ctx.queue.remove.mock.invocationCallOrder[0];
      const addOrder = ctx.queue.add.mock.invocationCallOrder[0];
      expect(removeOrder).toBeLessThan(addOrder);
    });

  it('drops trips that ended while parked, so the waiting count cannot lie',
    async () => {
      const ctx = makeDispatch(offPaused, { 't1': 'cancelled', 't2': 'requested' });
      const svc = await service(ctx);

      expect(await svc.resumeDeferred()).toBe(1);
      expect(ctx.queue.add).toHaveBeenCalledTimes(1);
    });

  it('resuming with nothing parked is a no-op', async () => {
    const ctx = makeDispatch(offPaused, {});
    const svc = await service(ctx);
    expect(await svc.resumeDeferred()).toBe(0);
    expect(ctx.queue.add).not.toHaveBeenCalled();
  });
});
