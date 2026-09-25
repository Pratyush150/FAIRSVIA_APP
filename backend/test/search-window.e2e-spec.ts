import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisKeys } from '../src/common/redis/redis.keys';
import { RedisService } from '../src/common/redis/redis.service';
import { RealtimeService } from '../src/realtime/realtime.service';
import { LocationService } from '../src/location/location.service';

/**
 * The search window: a ride booked with no driver of its tier nearby keeps
 * searching (status stays matching) for SEARCH_WINDOW_SEC; a driver of that
 * tier who comes online inside the window is offered it; with nobody, the
 * trip ends no_drivers only once the window is over. A short window here.
 */
const WINDOW_S = 8;

describe('Ride search window (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  let emit: jest.SpyInstance;
  const userIds: string[] = [];
  const prevWindow = process.env.SEARCH_WINDOW_SEC;
  const prevRescan = process.env.SEARCH_RESCAN_SEC;

  const login = async () => {
    const phone = `+1996${Math.floor(1e6 + Math.random() * 8e6)}`;
    await redis.client.del(`otp:rate:${phone}`);
    const r1 = await request(server).post('/api/v1/auth/otp/request').send({ phone });
    const r2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone, code: r1.body.devCode });
    userIds.push(r2.body.user.id);
    return {
      id: r2.body.user.id as string,
      auth: { Authorization: `Bearer ${r2.body.accessToken}` },
    };
  };
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  const statusOf = async (id: string) =>
    (await prisma.trip.findUniqueOrThrow({ where: { id } })).status;
  const book = async (pin: { lat: number; lng: number }) => {
    const rider = await login();
    const created = await request(server)
      .post('/api/v1/trips')
      .set(rider.auth)
      .send({
        pickupLat: pin.lat,
        pickupLng: pin.lng,
        dropoffLat: pin.lat + 0.02,
        dropoffLng: pin.lng + 0.02,
        tier: 'comfort',
      });
    expect(created.status).toBe(201);
    return { rider, tripId: created.body.id as string };
  };

  beforeAll(async () => {
    process.env.SEARCH_WINDOW_SEC = String(WINDOW_S);
    process.env.SEARCH_RESCAN_SEC = '5';
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api/v1', {
      exclude: [{ path: 'metrics', method: RequestMethod.GET }],
    });
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
    );
    await app.init();
    server = app.getHttpServer();
    prisma = app.get(PrismaService);
    redis = app.get(RedisService);
    emit = jest.spyOn(app.get(RealtimeService), 'emitToUser');
  });

  afterAll(async () => {
    process.env.SEARCH_WINDOW_SEC = prevWindow;
    process.env.SEARCH_RESCAN_SEC = prevRescan;
    if (prevWindow === undefined) delete process.env.SEARCH_WINDOW_SEC;
    if (prevRescan === undefined) delete process.env.SEARCH_RESCAN_SEC;
    await prisma.trip.deleteMany({ where: { riderId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  it('keeps searching with no driver, then ends no_drivers only after the window', async () => {
    const { rider, tripId } = await book({ lat: 7.301, lng: 7.301 });
    const started = Date.now();
    emit.mockClear();

    await wait(3000);
    // Well inside the window: still searching, not failed.
    expect(await statusOf(tripId)).toBe('matching');
    const matching = emit.mock.calls.find(
      ([u, e]) => u === rider.id && e === 'trip:matching',
    );
    // (the matching event may have fired before mockClear; the status is what counts)
    if (matching) expect(matching[2]).toMatchObject({ tripId, searchWindowSec: WINDOW_S });

    let status = await statusOf(tripId);
    for (let i = 0; i < 150 && status === 'matching'; i++) {
      await wait(100);
      status = await statusOf(tripId);
    }
    const elapsed = Date.now() - started;
    expect(status).toBe('no_drivers');
    expect(elapsed).toBeGreaterThanOrEqual((WINDOW_S - 1) * 1000);
    expect(emit).toHaveBeenCalledWith(rider.id, 'trip:no_drivers', { tripId });
  }, 30_000);

  it('offers the waiting ride to a driver of that tier who comes online inside the window', async () => {
    const pin = { lat: 7.401, lng: 7.401 };
    const { rider, tripId } = await book(pin);
    const driverId = `e2e-comfort-late-${Date.now()}`;
    try {
      await wait(2000);
      expect(await statusOf(tripId)).toBe('matching');
      emit.mockClear();

      // The driver comes online (status + tier) and sends a first GPS fix —
      // the real LocationService path that adds them to the comfort pool.
      await redis.client.set(RedisKeys.driverStatus(driverId), 'online');
      await redis.client.set(RedisKeys.driverTier(driverId), 'comfort');
      const joined = Date.now();
      await app.get(LocationService).ingest(driverId, { lat: pin.lat + 0.002, lng: pin.lng });

      const offered = () =>
        emit.mock.calls.find(([u, e]) => u === driverId && e === 'trip:offer');
      for (let i = 0; i < 80 && !offered(); i++) await wait(50);
      expect(offered()).toBeDefined();
      expect(offered()![2]).toMatchObject({ tripId, tier: 'comfort' });
      // Woken by the pool change, not the 5 s rescan tick.
      expect(Date.now() - joined).toBeLessThan(2500);
    } finally {
      await request(server)
        .post(`/api/v1/trips/${tripId}/cancel`)
        .set(rider.auth)
        .send({ reason: 'e2e' });
      await redis.client.set(RedisKeys.dispatchResponse(tripId), `0:${driverId}`, 'PX', 30000);
      await redis.client.zrem(RedisKeys.driversGeo('comfort'), driverId);
      await redis.client.del(
        RedisKeys.driverStatus(driverId),
        RedisKeys.driverTier(driverId),
        RedisKeys.driverOfferLock(driverId),
        RedisKeys.driverLoc(driverId),
      );
    }
  }, 30_000);

  it('a rider can cancel mid-window; the search stops without no_drivers', async () => {
    const { rider, tripId } = await book({ lat: 7.501, lng: 7.501 });
    await wait(2000);
    expect(await statusOf(tripId)).toBe('matching');
    emit.mockClear();
    const res = await request(server)
      .post(`/api/v1/trips/${tripId}/cancel`)
      .set(rider.auth)
      .send({ reason: 'e2e' });
    expect(res.status).toBeLessThan(300);
    await wait((WINDOW_S + 1) * 1000);
    expect(await statusOf(tripId)).toBe('cancelled');
    expect(emit).not.toHaveBeenCalledWith(rider.id, 'trip:no_drivers', expect.anything());
  }, 30_000);
});
