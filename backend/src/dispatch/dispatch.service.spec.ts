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
      },
    };
    const queue = { add: jest.fn().mockResolvedValue({}) };
    const favorites = {
      favoriteDriverIds: jest.fn().mockResolvedValue(new Set<string>()),
    };
    const geo = { route: jest.fn() };
    const realtime = { emitToUser: jest.fn() };
    const svc = new DispatchService(
      {} as never,
      redis as never,
      realtime as never,
      {} as never,
      {} as never,
      favorites as never,
      geo as never,
      queue as never,
    );
    return { svc, redis, queue, favorites, realtime };
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
      offerTo: (driverId: string, trip: unknown, rider: unknown) => Promise<boolean>;
      awaitResponse: () => Promise<boolean>;
      assign: () => Promise<boolean>;
      approachDistanceM: () => Promise<number | undefined>;
    };

    it('emits trip:offer_expired to the driver and returns false', async () => {
      const { svc, redis, realtime } = make();
      redis.client.set.mockResolvedValue('OK'); // offer lock acquired
      const internals = svc as unknown as Internals;
      internals.awaitResponse = jest.fn().mockResolvedValue(true); // driver accepted
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
      internals.awaitResponse = jest.fn().mockResolvedValue(true);
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
  });

  it('evictStale keeps fresh drivers and evicts ghosts (stale GPS) from the pool', async () => {
    const { svc, redis } = make();
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
    const svc = new DispatchService(
      prisma as never,
      {} as never,
      realtime as never,
      notifications as never,
      stateMachine as never,
      favorites as never,
      { route: jest.fn() } as never,
      {} as never,
    );
    // Skip the real inter-sweep delay so the test is fast.
    (svc as unknown as { sleep: () => Promise<void> }).sleep = () => Promise.resolve();
    return { svc, trip, prisma, realtime, stateMachine };
  }

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
