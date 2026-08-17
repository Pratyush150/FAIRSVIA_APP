import { TripStatus } from '@prisma/client';
import { RatingsService } from './ratings.service';

/**
 * Verifies the two-way rating rules and that the ratee's average is written from
 * the authoritative aggregate over the Rating rows (recomputed in a serializable
 * transaction — no incremental read-modify-write, so concurrent ratings can't
 * lose an update or drift the mean).
 */
describe('RatingsService', () => {
  function makeTx(agg: { avg: number; count: number }) {
    const tx = {
      rating: {
        upsert: jest.fn().mockImplementation(({ create, update }: any) => ({
          id: 'rt1',
          tags: (create ?? update).tags ?? [],
          stars: (create ?? update).stars,
          comment: (create ?? update).comment,
        })),
        aggregate: jest.fn().mockResolvedValue({
          _avg: { stars: agg.avg },
          _count: agg.count,
        }),
      },
      user: {
        update: jest.fn().mockResolvedValue({}),
      },
    };
    return tx;
  }

  function makeService(trip: unknown, tx: ReturnType<typeof makeTx>) {
    const prisma = {
      trip: { findUnique: jest.fn().mockResolvedValue(trip) },
      $transaction: jest.fn((cb: (t: unknown) => unknown) => cb(tx)),
    } as never;
    return new RatingsService(prisma);
  }

  const completedTrip = {
    id: 't1',
    riderId: 'r1',
    driverId: 'd1',
    status: TripStatus.completed,
  };

  it('writes the ratee average + count from the authoritative aggregate', async () => {
    const tx = makeTx({ avg: 4, count: 1 });
    const svc = makeService(completedTrip, tx);

    const res = await svc.rateTrip('r1', 't1', { stars: 4 });

    expect(res.toUser).toBe('d1');
    expect(tx.user.update).toHaveBeenCalledWith({
      where: { id: 'd1' },
      data: { ratingAvg: 4, ratingCount: 1 },
    });
  });

  it('folds a new rating into the average (from the aggregate)', async () => {
    const tx = makeTx({ avg: 4, count: 2 });
    const svc = makeService(completedTrip, tx);

    await svc.rateTrip('r1', 't1', { stars: 3 });

    expect(tx.user.update).toHaveBeenCalledWith({
      where: { id: 'd1' },
      data: { ratingAvg: 4, ratingCount: 2 },
    });
  });

  it('rounds the aggregate average to 2 decimals', async () => {
    const tx = makeTx({ avg: 4.666666, count: 3 });
    const svc = makeService(completedTrip, tx);

    await svc.rateTrip('r1', 't1', { stars: 5 });

    expect(tx.user.update).toHaveBeenCalledWith({
      where: { id: 'd1' },
      data: { ratingAvg: 4.67, ratingCount: 3 },
    });
  });

  it('lets the driver rate the rider (direction flips)', async () => {
    const tx = makeTx({ avg: 5, count: 1 });
    const svc = makeService(completedTrip, tx);

    const res = await svc.rateTrip('d1', 't1', { stars: 5 });

    expect(res.toUser).toBe('r1');
  });

  it('rejects rating a trip that is not completed', async () => {
    const tx = makeTx({ avg: 5, count: 0 });
    const svc = makeService(
      { ...completedTrip, status: TripStatus.in_progress },
      tx,
    );
    await expect(svc.rateTrip('r1', 't1', { stars: 5 })).rejects.toThrow(
      'completed',
    );
  });

  it('rejects a rating from a non-participant', async () => {
    const tx = makeTx({ avg: 5, count: 0 });
    const svc = makeService(completedTrip, tx);
    await expect(
      svc.rateTrip('stranger', 't1', { stars: 5 }),
    ).rejects.toThrow('Not your trip');
  });
});
