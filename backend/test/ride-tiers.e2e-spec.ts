import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisKeys } from '../src/common/redis/redis.keys';
import { RedisService } from '../src/common/redis/redis.service';
import { RealtimeService } from '../src/realtime/realtime.service';

/**
 * Auto-rickshaw and bike-taxi ride types (Pune pilot): a driver can register
 * as one, riders are quoted for them, and dispatch only offers an auto ride to
 * auto drivers and a bike ride to bike drivers.
 */
describe('Auto and bike ride types (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  let emit: jest.SpyInstance;
  const userIds: string[] = [];

  const login = async () => {
    const phone = `+1997${Math.floor(1e6 + Math.random() * 8e6)}`;
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

  beforeAll(async () => {
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

  // Only rows this suite created. app.close() drains in-flight BullMQ jobs.
  afterAll(async () => {
    await prisma.trip.deleteMany({ where: { riderId: { in: userIds } } });
    await prisma.driverProfile.deleteMany({ where: { userId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  it.each([
    ['auto', 'Bajaj', 'RE Compact'],
    ['bike', 'Honda', 'Activa 6G'],
  ])('a driver can register a %s', async (tier, make, model) => {
    const driver = await login();
    const res = await request(server)
      .post('/api/v1/drivers/onboarding')
      .set(driver.auth)
      .send({
        vehicleMake: make,
        vehicleModel: model,
        plateNumber: `T${tier.toUpperCase()}${Date.now() % 100000}`,
        vehicleTier: tier,
      });
    expect(res.status).toBe(201);
    const profile = await prisma.driverProfile.findUnique({
      where: { userId: driver.id },
    });
    expect(profile?.vehicleTier).toBe(tier);
  });

  it('rejects a vehicle type that does not exist', async () => {
    const driver = await login();
    await request(server)
      .post('/api/v1/drivers/onboarding')
      .set(driver.auth)
      .send({
        vehicleMake: 'Tata',
        vehicleModel: 'Ace',
        plateNumber: `TRUCK${Date.now() % 100000}`,
        vehicleTier: 'truck',
      })
      .expect(400);
  });

  /**
   * One parked driver per pool at the same remote spot (so no real driver is
   * near). Booking tier T must offer to T's driver and to nobody else.
   */
  it.each([
    ['auto', 7.001],
    ['bike', 7.101],
  ])('offers a %s ride only to a driver of that type', async (tier, lat) => {
    const pin = { lat, lng: lat };
    const stamp = Date.now();
    const parked: Record<string, string> = {};
    for (const t of ['economy', 'auto', 'bike']) {
      const id = `e2e-${t}-drv-${stamp}`;
      parked[t] = id;
      await redis.client.geoadd(RedisKeys.driversGeo(t), pin.lng, pin.lat, id);
      await redis.client.set(RedisKeys.driverStatus(id), 'online');
      // A fresh GPS ping, or dispatch evicts the driver as a ghost.
      await redis.client.hset(RedisKeys.driverLoc(id), 'ts', String(Date.now()));
    }
    const rider = await login();
    emit.mockClear();

    const created = await request(server)
      .post('/api/v1/trips')
      .set(rider.auth)
      .send({
        pickupLat: pin.lat,
        pickupLng: pin.lng,
        dropoffLat: pin.lat + 0.02,
        dropoffLng: pin.lng + 0.02,
        tier,
      });
    expect(created.status).toBe(201);
    expect(created.body.tier).toBe(tier);
    const tripId = created.body.id as string;

    try {
      const offeredTo = () =>
        emit.mock.calls
          .filter(([, event]) => event === 'trip:offer')
          .map(([userId]) => userId as string);
      for (let i = 0; i < 150 && offeredTo().length === 0; i++) {
        await new Promise((r) => setTimeout(r, 100));
      }
      expect(offeredTo()).toEqual([parked[tier]]);
    } finally {
      // Release the dispatch loop and clear the parked drivers.
      await request(server)
        .post(`/api/v1/trips/${tripId}/cancel`)
        .set(rider.auth)
        .send({ reason: 'e2e' });
      await redis.client.set(
        RedisKeys.dispatchResponse(tripId),
        `0:${parked[tier]}`,
        'PX',
        30000,
      );
      for (const [t, id] of Object.entries(parked)) {
        await redis.client.zrem(RedisKeys.driversGeo(t), id);
        await redis.client.del(
          RedisKeys.driverStatus(id),
          RedisKeys.driverOfferLock(id),
          RedisKeys.driverLoc(id),
        );
      }
    }
  }, 30_000);
});
