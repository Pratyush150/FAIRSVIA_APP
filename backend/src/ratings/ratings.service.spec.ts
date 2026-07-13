import { TripStatus } from '@prisma/client';
import { RatingsService } from './ratings.service';

/**
 * Verifies the two-way rating rules and, crucially, the incremental average
 * update — we never rescan history, so the running mean must be exact.
 */
describe('RatingsService', () => {
  function makeTx(ratee: { ratingAvg: number; ratingCount: number } | null) {
    const tx = {
      rating: {
        findUnique: jest.fn(),
        upsert: jest
          .fn()
          .mockImplementation(({ create, update }: any) => ({
            id: 'rt1',
            tags: (create ?? update).tags ?? [],
            stars: (create ?? update).stars,
            comment: (create ?? update).comment,
          })),
      },
      user: {
        findUnique: jest.fn().mockResolvedValue(ratee),
        update: jest.fn().mockResolvedValue({}),
      },
    };
    return tx;
  }

  function makeService(trip: unknown, tx: ReturnType<typeof makeTx>) {
    const prisma = {
      trip: { findUnique: jest.fn().mockResolvedValue(trip) },
      rating: { findUnique: jest.fn() },
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

  it('adds a first driver rating and sets the average to those stars', async () => {
    // Driver starts at the default 5.00 / 0 ratings.
    const tx = makeTx({ ratingAvg: 5, ratingCount: 0 });
    tx.rating.findUnique.mockResolvedValue(null);
    const svc = makeService(completedTrip, tx);

    const res = await svc.rateTrip('r1', 't1', { stars: 4 });

    expect(res.toUser).toBe('d1');
    expect(tx.user.update).toHaveBeenCalledWith({
      where: { id: 'd1' },
      data: { ratingAvg: 4, ratingCount: 1 },
    });
  });

  it('folds a new rating into the running average', async () => {
    // Driver at 5.00 across 1 rating; a new 3-star pulls it to 4.00 / 2.
    const tx = makeTx({ ratingAvg: 5, ratingCount: 1 });
    tx.rating.findUnique.mockResolvedValue(null);
    const svc = makeService(completedTrip, tx);

    await svc.rateTrip('r1', 't1', { stars: 3 });

    expect(tx.user.update).toHaveBeenCalledWith({
      where: { id: 'd1' },
      data: { ratingAvg: 4, ratingCount: 2 },
    });
  });

  it('replaces the old star value when re-rating (count unchanged)', async () => {
    // Ratee avg 4.00 / 2 ratings; this rater previously gave 2 stars, now 4.
    // total = 4*2 - 2 + 4 = 10 → 10/2 = 5.00, count still 2.
    const tx = makeTx({ ratingAvg: 4, ratingCount: 2 });
    tx.rating.findUnique.mockResolvedValue({ stars: 2 });
    const svc = makeService(completedTrip, tx);

    await svc.rateTrip('r1', 't1', { stars: 4 });

    expect(tx.user.update).toHaveBeenCalledWith({
      where: { id: 'd1' },
      data: { ratingAvg: 5, ratingCount: 2 },
    });
  });

  it('lets the driver rate the rider (direction flips)', async () => {
    const tx = makeTx({ ratingAvg: 5, ratingCount: 0 });
    tx.rating.findUnique.mockResolvedValue(null);
    const svc = makeService(completedTrip, tx);

    const res = await svc.rateTrip('d1', 't1', { stars: 5 });

    expect(res.toUser).toBe('r1');
  });

  it('rejects rating a trip that is not completed', async () => {
    const tx = makeTx({ ratingAvg: 5, ratingCount: 0 });
    const svc = makeService(
      { ...completedTrip, status: TripStatus.in_progress },
      tx,
    );
    await expect(svc.rateTrip('r1', 't1', { stars: 5 })).rejects.toThrow(
      'completed',
    );
  });

  it('rejects a rating from a non-participant', async () => {
    const tx = makeTx({ ratingAvg: 5, ratingCount: 0 });
    const svc = makeService(completedTrip, tx);
    await expect(
      svc.rateTrip('stranger', 't1', { stars: 5 }),
    ).rejects.toThrow('Not your trip');
  });
});
