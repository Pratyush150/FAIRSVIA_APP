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
    const svc = new DispatchService(
      {} as never,
      redis as never,
      {} as never,
      {} as never,
      {} as never,
      favorites as never,
      geo as never,
      queue as never,
    );
    return { svc, redis, queue, favorites };
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
