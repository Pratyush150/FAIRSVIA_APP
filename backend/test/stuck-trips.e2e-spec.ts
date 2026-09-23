import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';
import { RealtimeService } from '../src/realtime/realtime.service';
import { StuckTripSweeper } from '../src/dispatch/stuck-trip-sweeper';

/** Ride searches whose job was lost must end, not hang for ever. */
describe('Stuck ride sweeper (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let redis: RedisService;
  let sweeper: StuckTripSweeper;
  let emit: jest.SpyInstance;
  const userIds: string[] = [];
  const deferredIds: string[] = [];

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    await app.init();
    prisma = app.get(PrismaService);
    redis = app.get(RedisService);
    sweeper = app.get(StuckTripSweeper);
    emit = jest.spyOn(app.get(RealtimeService), 'emitToUser');
  });

  afterAll(async () => {
    if (deferredIds.length) await redis.client.srem('dispatch:deferred', ...deferredIds);
    await prisma.trip.deleteMany({ where: { riderId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  const rider = async () => {
    const u = await prisma.user.create({
      data: { phone: `+1999${Math.floor(1e6 + Math.random() * 8e6)}` },
    });
    userIds.push(u.id);
    return u.id;
  };
  const trip = async (status: string, minutesAgo: number, extra: object = {}) =>
    prisma.trip.create({
      data: {
        riderId: await rider(),
        status: status as never,
        pickupLat: 41.31,
        pickupLng: 69.24,
        dropoffLat: 41.33,
        dropoffLng: 69.28,
        requestedAt: new Date(Date.now() - minutesAgo * 60_000),
        ...extra,
      },
    });
  const statusOf = async (id: string) =>
    (await prisma.trip.findUniqueOrThrow({ where: { id } })).status;

  it('ends orphaned searches, tells the rider, and leaves everything else alone', async () => {
    const orphanedSearch = await trip('matching', 20);
    const neverStarted = await trip('requested', 20);
    const liveSearch = await trip('matching', 1);
    const paused = await trip('requested', 20);
    const scheduled = await trip('scheduled', 60, {
      scheduledAt: new Date(Date.now() + 3600_000),
    });
    const onTheWay = await trip('accepted', 30);
    deferredIds.push(paused.id);
    await redis.client.sadd('dispatch:deferred', paused.id);
    await redis.client.del('dispatch:stuck-sweeper:lock');
    emit.mockClear();

    const ended = await sweeper.sweep();

    expect(await statusOf(orphanedSearch.id)).toBe('no_drivers');
    expect(await statusOf(neverStarted.id)).toBe('expired');
    expect(await statusOf(liveSearch.id)).toBe('matching');
    expect(await statusOf(paused.id)).toBe('requested');
    expect(await statusOf(scheduled.id)).toBe('scheduled');
    expect(await statusOf(onTheWay.id)).toBe('accepted');
    // At least these two; other suites' leftovers may be swept too.
    expect(ended).toBeGreaterThanOrEqual(2);
    for (const t of [orphanedSearch, neverStarted]) {
      expect(emit).toHaveBeenCalledWith(t.riderId, 'trip:no_drivers', { tripId: t.id });
    }
  });

  it('runs on one instance at a time', async () => {
    await redis.client.del('dispatch:stuck-sweeper:lock');
    const [a, b] = await Promise.all([sweeper.sweep(), sweeper.sweep()]);
    // The loser of the lock does nothing at all.
    expect([a, b]).toContain(0);
    expect(await redis.client.exists('dispatch:stuck-sweeper:lock')).toBe(1);
  });
});
