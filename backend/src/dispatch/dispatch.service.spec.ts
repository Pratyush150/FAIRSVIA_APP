import { DispatchService } from './dispatch.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { DISPATCH_JOB } from '../common/queue/queue.constants';

describe('DispatchService', () => {
  function make() {
    const redis = {
      client: {
        get: jest.fn(),
        set: jest.fn().mockResolvedValue('OK'),
        del: jest.fn().mockResolvedValue(1),
        sadd: jest.fn().mockResolvedValue(1),
        expire: jest.fn().mockResolvedValue(1),
        smembers: jest.fn().mockResolvedValue([]),
        hmget: jest.fn().mockResolvedValue([null, null]),
        hset: jest.fn().mockResolvedValue(1),
      },
    };
    const queue = { add: jest.fn().mockResolvedValue({}) };
    const favorites = {
      favoriteDriverIds: jest.fn().mockResolvedValue(new Set<string>()),
    };
    const geo = { route: jest.fn() };
    const realtime = { emitToUser: jest.fn() };
    const prisma = { trip: { findUnique: jest.fn().mockResolvedValue(null) } };
    const drivers = { forceOffline: jest.fn().mockResolvedValue(true) };
    const surge = { releaseDemand: jest.fn().mockResolvedValue(undefined) };
    const svc = new DispatchService(
      prisma as never,
      redis as never,
      realtime as never,
      {} as never,
      {} as never,
      favorites as never,
      geo as never,
      queue as never,
      drivers as never,
      surge as never,
    );
    return { svc, redis, queue, favorites, realtime, prisma, drivers, surge, geo };
  }

  it('dispatchTrip enqueues a durable job keyed by tripId (de-dupe)', async () => {
    const { svc, queue } = make();
    await svc.dispatchTrip('trip-1');
    expect(queue.add).toHaveBeenCalledTimes(1);
    const [job, data, opts] = queue.add.mock.calls[0];
    expect(job).toBe(DISPATCH_JOB);
    expect(data).toEqual({ tripId: 'trip-1' });
    expect(opts.jobId).toBe('trip-1');
  });

  it('respondToOffer records the response for the currently-offered driver', async () => {
    const { svc, redis } = make();
    redis.client.get.mockResolvedValue('driver-A'); // current offeree
    const ok = await svc.respondToOffer('driver-A', 'trip-1', true);
    expect(ok).toBe(true);
    expect(redis.client.set).toHaveBeenCalledWith(
      RedisKeys.dispatchResponse('trip-1'),
      '1:driver-A',
      'PX',
      30000,
    );
  });

  it('respondToOffer rejects a response from a driver who is not the offeree', async () => {
    const { svc, redis } = make();
    redis.client.get.mockResolvedValue('driver-A');
    const ok = await svc.respondToOffer('driver-B', 'trip-1', true);
    expect(ok).toBe(false);
    expect(redis.client.set).not.toHaveBeenCalled();
  });

  it('respondToOffer returns false when the offer has expired (no offeree)', async () => {
    const { svc, redis } = make();
    redis.client.get.mockResolvedValue(null);
    const ok = await svc.respondToOffer('driver-A', 'trip-1', false);
    expect(ok).toBe(false);
  });

  // A late/foreign ACCEPT must tell the driver the offer is gone; otherwise the
  // driver app waits forever for a trip:assigned that will never arrive.
  it('respondToOffer(accept) on an expired offer emits trip:offer_expired to that driver', async () => {
    const { svc, redis, realtime } = make();
    redis.client.get.mockResolvedValue(null);
    const ok = await svc.respondToOffer('driver-A', 'trip-1', true);
    expect(ok).toBe(false);
    expect(realtime.emitToUser).toHaveBeenCalledWith('driver-A', 'trip:offer_expired', {
      tripId: 'trip-1',
    });
  });

  it('respondToOffer(decline) on an expired offer stays silent', async () => {
    const { svc, redis, realtime } = make();
    redis.client.get.mockResolvedValue(null);
    await svc.respondToOffer('driver-A', 'trip-1', false);
    expect(realtime.emitToUser).not.toHaveBeenCalled();
  });

  // A double-tap / REST retry of accept after the socket accept already won:
  // the offer key is gone, but the trip IS this driver's — offer_expired here
  // would make the app abandon a live trip.
  it('a duplicate accept for an already-assigned trip is ok:true and never offer_expired', async () => {
    const { svc, redis, realtime, prisma } = make();
    redis.client.get.mockResolvedValue(null); // offer key already cleared
    prisma.trip.findUnique.mockResolvedValue({ driverId: 'driver-A', status: 'accepted' });
    await expect(svc.respondToOffer('driver-A', 'trip-1', true)).resolves.toBe(true);
    expect(realtime.emitToUser).not.toHaveBeenCalled();
    expect(redis.client.set).not.toHaveBeenCalled();
  });

  it('an accept for a trip assigned to SOMEONE ELSE still gets offer_expired', async () => {
    const { svc, redis, realtime, prisma } = make();
    redis.client.get.mockResolvedValue(null);
    prisma.trip.findUnique.mockResolvedValue({ driverId: 'driver-B', status: 'accepted' });
    await expect(svc.respondToOffer('driver-A', 'trip-1', true)).resolves.toBe(false);
    expect(realtime.emitToUser).toHaveBeenCalledWith('driver-A', 'trip:offer_expired', { tripId: 'trip-1' });
  });

  // offerTo: the driver accepted in time, but assign() could not commit the
  // trip (rider cancelled during the window / driver already bound to another
  // trip). Previously nothing was emitted on this branch.
  describe('offerTo when the accepted offer fails to assign', () => {
    const trip = {
      id: 'trip-1',
      status: 'matching',
      riderId: 'rider-1',
      tier: 'economy',
      pickupLat: 25.7,
      pickupLng: -80.2,
      dropoffLat: 25.8,
      dropoffLng: -80.3,
      fareEstimate: 12,
      distanceM: 5000,
      durationS: 600,
    };
    type Internals = {
      offerTo: (
        driverId: string,
        trip: unknown,
        rider: unknown,
        approach?: Map<string, unknown>,
      ) => Promise<boolean>;
      awaitResponse: () => Promise<'accepted' | 'declined' | 'timeout'>;
      assign: () => Promise<boolean>;
      approachDistanceM: () => Promise<number | undefined>;
    };

    it('emits trip:offer_expired to the driver and returns false', async () => {
      const { svc, redis, realtime } = make();
      redis.client.set.mockResolvedValue('OK'); // offer lock acquired
      const internals = svc as unknown as Internals;
      internals.awaitResponse = jest.fn().mockResolvedValue('accepted'); // driver accepted
      internals.assign = jest.fn().mockResolvedValue(false); // ...but couldn't be committed
      internals.approachDistanceM = jest.fn().mockResolvedValue(undefined);

      const ok = await internals.offerTo('driver-A', trip, { name: 'Priya', rating: 4.8 });

      expect(ok).toBe(false);
      expect(realtime.emitToUser).toHaveBeenCalledWith('driver-A', 'trip:offer_expired', {
        tripId: 'trip-1',
      });
    });

    it('does not emit trip:offer_expired when the assignment succeeds', async () => {
      const { svc, redis, realtime } = make();
      redis.client.set.mockResolvedValue('OK');
      const internals = svc as unknown as Internals;
      internals.awaitResponse = jest.fn().mockResolvedValue('accepted');
      internals.assign = jest.fn().mockResolvedValue(true);
      internals.approachDistanceM = jest.fn().mockResolvedValue(undefined);

      const ok = await internals.offerTo('driver-A', trip, { name: 'Priya', rating: 4.8 });

      expect(ok).toBe(true);
      expect(realtime.emitToUser).not.toHaveBeenCalledWith(
        'driver-A',
        'trip:offer_expired',
        expect.anything(),
      );
    });

    // The offer card: road approach numbers from the ranking route when we
    // have them, straight-line otherwise, plus dropoff/duration/surge.
    it('trip:offer carries road approach ETA/distance from the cached ranking route, plus dropoff/durationS/surge', async () => {
      const { svc, redis, realtime } = make();
      redis.client.set.mockResolvedValue('OK');
      const internals = svc as unknown as Internals;
      internals.awaitResponse = jest.fn().mockResolvedValue('timeout');
      const cache = new Map([['driver-A', { distanceM: 1840, durationS: 312, polyline: 'abc' }]]);

      await internals.offerTo('driver-A', { ...trip, surgeMultiplier: 1.3, dropoffAddr: '1 Main St' }, { name: 'Priya', rating: 4.8 }, cache);

      const offer = realtime.emitToUser.mock.calls.find((c) => c[1] === 'trip:offer')![2];
      expect(offer).toMatchObject({
        tripId: 'trip-1',
        dropoff: { lat: 25.8, lng: -80.3, address: '1 Main St' },
        durationS: 600,
        surge: 1.3,
        approachDistanceM: 1840,
        approachEtaS: 312,
        approachSource: 'road',
      });
    });

    it('trip:offer falls back to straight-line approach numbers when no route was cached', async () => {
      const { svc, redis, realtime } = make();
      redis.client.set.mockResolvedValue('OK');
      // Driver 1 km due north of the pickup.
      redis.client.hmget.mockResolvedValue([String(25.7 + 0.009), String(-80.2)]);
      const internals = svc as unknown as Internals;
      internals.awaitResponse = jest.fn().mockResolvedValue('timeout');

      await internals.offerTo('driver-A', trip, { name: 'Priya', rating: 4.8 }, new Map());

      const offer = realtime.emitToUser.mock.calls.find((c) => c[1] === 'trip:offer')![2];
      expect(offer.approachSource).toBe('straight');
      expect(offer.approachDistanceM).toBeGreaterThan(950);
      expect(offer.approachDistanceM).toBeLessThan(1050);
      expect(offer.approachEtaS).toBe(Math.round(offer.approachDistanceM / 8));
      expect(offer.surge).toBe(1);
    });

    it('an explicit decline records the driver in the per-trip declined set; a timeout does not', async () => {
      const { svc, redis } = make();
      redis.client.set.mockResolvedValue('OK');
      const internals = svc as unknown as Internals;
      internals.approachDistanceM = jest.fn().mockResolvedValue(undefined);

      internals.awaitResponse = jest.fn().mockResolvedValue('declined');
      await internals.offerTo('driver-A', trip, { name: 'Priya', rating: 4.8 });
      expect(redis.client.sadd).toHaveBeenCalledWith(RedisKeys.dispatchDeclined('trip-1'), 'driver-A');

      redis.client.sadd.mockClear();
      internals.awaitResponse = jest.fn().mockResolvedValue('timeout');
      await internals.offerTo('driver-B', trip, { name: 'Priya', rating: 4.8 });
      expect(redis.client.sadd).not.toHaveBeenCalled();
    });
  });

  it('sweep never re-offers a trip to a driver who declined it', async () => {
    const { svc, redis, prisma } = make();
    redis.client.smembers.mockResolvedValue(['driver-A']); // declined earlier
    redis.client.get.mockImplementation(async (k: string) =>
      k.endsWith(':status') ? 'online' : null,
    );
    prisma.trip.findUnique.mockResolvedValue({ status: 'matching' });
    const internals = svc as unknown as {
      nearestDrivers: jest.Mock;
      rankByRoadEta: jest.Mock;
      offerTo: jest.Mock;
      sweep: (t: unknown, f: Set<string>, r: unknown, d: number) => Promise<string>;
    };
    internals.nearestDrivers = jest.fn().mockResolvedValue(['driver-A', 'driver-B']);
    internals.rankByRoadEta = jest.fn(async (_t: unknown, c: string[]) => c);
    internals.offerTo = jest.fn().mockResolvedValue(false);

    const trip = { id: 'trip-1', tier: 'economy', pickupLat: 25.7, pickupLng: -80.2 };
    await internals.sweep(trip, new Set(), { name: 'R', rating: 5 }, Date.now() + 60000);

    const offered = internals.offerTo.mock.calls.map((c) => c[0]);
    expect(offered).toEqual(['driver-B']); // `tried` de-dupes across rings; A is never offered
  });

  it('rankByRoadEta caches each candidate route for the offer card', async () => {
    const { svc, geo, redis } = make();
    redis.client.hmget.mockResolvedValue(['25.7', '-80.2']);
    geo.route
      .mockResolvedValueOnce({ distanceM: 3000, durationS: 400, polyline: 'x' })
      .mockResolvedValueOnce({ distanceM: 1000, durationS: 120, polyline: 'y' });
    const cache = new Map();
    const ranked = await (
      svc as unknown as {
        rankByRoadEta: (t: unknown, c: string[], f: Set<string>, m: Map<string, unknown>) => Promise<string[]>;
      }
    ).rankByRoadEta({ id: 'trip-1', pickupLat: 25.71, pickupLng: -80.21 }, ['far', 'near'], new Set(), cache);
    expect(ranked).toEqual(['near', 'far']);
    expect(cache.get('near')).toMatchObject({ durationS: 120 });
    expect(cache.get('far')).toMatchObject({ durationS: 400 });
  });

  it('evictStale keeps fresh drivers and evicts ghosts (stale GPS) from the pool', async () => {
    const { svc, redis, drivers } = make();
    const now = Date.now();
    const ts: Record<string, string> = {
      fresh: String(now - 2000), // pinged 2s ago → still here
      ghost: String(now - 600000), // pinged 10min ago → gone
    };
    // pipeline().hget(...).exec() → [[null, ts], ...] in call order.
    const calls: string[] = [];
    (redis.client as Record<string, unknown>).pipeline = jest.fn(() => {
      const p: {
        hget: (k: string) => typeof p;
        exec: () => Promise<Array<[null, string]>>;
      } = {
        hget: (k: string) => {
          calls.push(k);
          return p;
        },
        exec: async () =>
          calls.map(
            (k) =>
              [null, k.includes('ghost') ? ts.ghost : ts.fresh] as [null, string],
          ),
      };
      return p;
    });
    (redis.client as Record<string, unknown>).zrem = jest.fn().mockResolvedValue(1);

    const fresh = await (
      svc as unknown as {
        evictStale(tier: string, ids: string[]): Promise<string[]>;
      }
    ).evictStale('economy', ['fresh', 'ghost']);

    expect(fresh).toEqual(['fresh']);
    expect(
      (redis.client as unknown as { zrem: jest.Mock }).zrem,
    ).toHaveBeenCalledWith(RedisKeys.driversGeo('economy'), 'ghost');
    // The ghost is taken fully offline (Redis + DB) and told why; the fresh
    // driver is untouched.
    expect(drivers.forceOffline).toHaveBeenCalledWith('ghost', 'economy', 'stale_location');
    expect(drivers.forceOffline).not.toHaveBeenCalledWith('fresh', expect.anything(), expect.anything());
  });

  it('favoritesFirst moves favourites to the front, keeping nearest order', () => {
    const { svc } = make();
    // `favoritesFirst` is a pure ordering helper on the distance-sorted list.
    const ordered = (
      svc as unknown as {
        favoritesFirst(c: string[], f: Set<string>): string[];
      }
    ).favoritesFirst(['a', 'b', 'c', 'd'], new Set(['c', 'a']));
    // Favourites 'a','c' keep their relative (nearest-first) order, then rest.
    expect(ordered).toEqual(['a', 'c', 'b', 'd']);
  });

  it('favoritesFirst is a no-op with no favourites', () => {
    const { svc } = make();
    const list = ['x', 'y', 'z'];
    const ordered = (
      svc as unknown as {
        favoritesFirst(c: string[], f: Set<string>): string[];
      }
    ).favoritesFirst(list, new Set<string>());
    expect(ordered).toEqual(list);
  });

  // The re-sweep loop is the fix for momentary supply exhaustion: an exhausted
  // sweep must NOT immediately fail the trip while a driver may still free up.
  function makeForDispatch() {
    const trip = { id: 'trip-1', status: 'matching', riderId: 'rider-1', tier: 'economy' };
    const prisma = {
      trip: { findUnique: jest.fn().mockResolvedValue(trip) },
    };
    const realtime = { emitToUser: jest.fn() };
    const notifications = { notifyTrip: jest.fn() };
    const stateMachine = { transition: jest.fn().mockResolvedValue(undefined) };
    const favorites = { favoriteDriverIds: jest.fn().mockResolvedValue(new Set<string>()) };
    const surge = { releaseDemand: jest.fn().mockResolvedValue(undefined) };
    const svc = new DispatchService(
      prisma as never,
      {} as never,
      realtime as never,
      notifications as never,
      stateMachine as never,
      favorites as never,
      { route: jest.fn() } as never,
      {} as never,
      { forceOffline: jest.fn() } as never,
      surge as never,
    );
    // Skip the real inter-sweep delay so the test is fast.
    (svc as unknown as { sleep: () => Promise<void> }).sleep = () => Promise.resolve();
    return { svc, trip, prisma, realtime, stateMachine, surge };
  }

  it('declares no_drivers once the window elapses and withdraws the rider from surge demand', async () => {
    const { svc, realtime, stateMachine, surge, prisma } = makeForDispatch();
    prisma.trip.findUnique.mockResolvedValue({
      id: 'trip-1', status: 'matching', riderId: 'rider-1', tier: 'economy', pickupLat: 25.7, pickupLng: -80.2,
    });
    (svc as unknown as { sweep: jest.Mock }).sweep = jest.fn().mockResolvedValue('exhausted');
    // Force the deadline to have passed after the first sweep.
    const realNow = Date.now;
    let calls = 0;
    Date.now = () => realNow() + (calls++ > 0 ? 120000 : 0);
    try {
      await svc.runDispatch('trip-1');
    } finally {
      Date.now = realNow;
    }
    expect(stateMachine.transition).toHaveBeenCalledWith(expect.objectContaining({ to: 'no_drivers' }));
    expect(realtime.emitToUser).toHaveBeenCalledWith('rider-1', 'trip:no_drivers', { tripId: 'trip-1' });
    expect(surge.releaseDemand).toHaveBeenCalledWith(25.7, -80.2, 'rider-1');
  });

  it('re-sweeps after an exhausted pass and assigns without declaring no_drivers', async () => {
    const { svc, realtime, stateMachine } = makeForDispatch();
    const sweep = jest
      .fn()
      .mockResolvedValueOnce('exhausted') // all drivers busy this pass...
      .mockResolvedValueOnce('assigned'); // ...one frees up on the next sweep
    (svc as unknown as { sweep: jest.Mock }).sweep = sweep;

    await svc.runDispatch('trip-1');

    expect(sweep).toHaveBeenCalledTimes(2);
    expect(stateMachine.transition).not.toHaveBeenCalled(); // stayed in MATCHING
    expect(realtime.emitToUser).not.toHaveBeenCalledWith(
      'rider-1',
      'trip:no_drivers',
      expect.anything(),
    );
  });

  it('stops re-sweeping and does not fail the trip once it leaves MATCHING (cancelled)', async () => {
    const { svc, prisma, stateMachine } = makeForDispatch();
    (svc as unknown as { sweep: jest.Mock }).sweep = jest
      .fn()
      .mockResolvedValue('exhausted');
    // Initial load = matching; the post-sweep cancel-check sees it cancelled.
    prisma.trip.findUnique
      .mockResolvedValueOnce({ id: 'trip-1', status: 'matching', riderId: 'rider-1', tier: 'economy' })
      .mockResolvedValueOnce({ status: 'cancelled' });

    await svc.runDispatch('trip-1');

    expect(stateMachine.transition).not.toHaveBeenCalled();
  });
});
