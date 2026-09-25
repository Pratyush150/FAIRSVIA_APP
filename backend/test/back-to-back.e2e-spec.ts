import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisKeys } from '../src/common/redis/redis.keys';
import { RedisService } from '../src/common/redis/redis.service';
import { LocationService } from '../src/location/location.service';
import { RealtimeService } from '../src/realtime/realtime.service';

/**
 * Owner bug: "the driver just completed the ride but while he is doing rating
 * etc. he doesn't get ride requests for that duration."
 *
 * Dispatch takes a driver out of the GEO pool at assignment; completion only
 * flipped their status back to 'online', and they re-entered the pool on the
 * NEXT GPS ping. A driver is offerable the moment the trip completes — with
 * no further ping, status call or rating.
 */
describe('Driver is offerable right after completing a trip (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  let location: LocationService;
  let emit: jest.SpyInstance;
  const userIds: string[] = [];

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

  const offersTo = (driverId: string, tripId: string) =>
    emit.mock.calls.filter(
      ([userId, event, data]) =>
        userId === driverId && event === 'trip:offer' && data?.tripId === tripId,
    ).length;

  const waitForOffer = async (driverId: string, tripId: string) => {
    for (let i = 0; i < 100 && offersTo(driverId, tripId) === 0; i++) {
      await new Promise((r) => setTimeout(r, 100));
    }
    return offersTo(driverId, tripId) > 0;
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
    location = app.get(LocationService);
    emit = jest.spyOn(app.get(RealtimeService), 'emitToUser');
  });

  afterAll(async () => {
    await prisma.trip.deleteMany({ where: { riderId: { in: userIds } } });
    await prisma.driverProfile.deleteMany({ where: { userId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  it('a second rider booking next to the drop-off is offered to the driver with no new ping', async () => {
    // A remote spot so no dev/simulator driver is nearer than ours.
    const base = { lat: 5.2 + Math.random() * 0.3, lng: 2.1 + Math.random() * 0.3 };
    const dropoff = { lat: base.lat + 0.01, lng: base.lng + 0.01 };

    const driver = await login();
    await request(server)
      .patch('/api/v1/users/me')
      .set(driver.auth)
      .send({ fullName: 'Back Toback' })
      .expect(200);
    await request(server)
      .post('/api/v1/drivers/onboarding')
      .set(driver.auth)
      .send({
        vehicleMake: 'Maruti Suzuki',
        vehicleModel: 'Dzire',
        plateNumber: `BTB${Date.now() % 100000}`,
        vehicleTier: 'economy',
      })
      .expect(201);
    await prisma.driverProfile.update({
      where: { userId: driver.id },
      data: { docsVerified: true },
    });
    await request(server)
      .post('/api/v1/drivers/status')
      .set(driver.auth)
      .send({ status: 'online' })
      .expect(200);
    await location.ingest(driver.id, { lat: base.lat, lng: base.lng, heading: 0, speed: 0 });

    const riderA = await login();
    const riderB = await login();

    // --- Trip A through to completion ---
    const a = await request(server)
      .post('/api/v1/trips')
      .set(riderA.auth)
      .send({
        pickupLat: base.lat, pickupLng: base.lng,
        dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
        tier: 'economy', paymentMode: 'cash',
      })
      .expect(201);
    const tripA = a.body.id as string;
    expect(await waitForOffer(driver.id, tripA)).toBe(true);
    await request(server).post(`/api/v1/trips/${tripA}/accept`).set(driver.auth).expect(200);
    for (let i = 0; i < 50; i++) {
      if ((await redis.client.get(RedisKeys.driverActiveTrip(driver.id))) === tripA) break;
      await new Promise((r) => setTimeout(r, 100));
    }
    // Assignment took the driver out of the pool.
    expect(await redis.client.geopos(RedisKeys.driversGeo('economy'), driver.id)).toEqual([null]);
    await request(server).post(`/api/v1/trips/${tripA}/arrived`).set(driver.auth).expect(200);
    const otp = (await prisma.trip.findUnique({ where: { id: tripA } }))!.startOtp;
    await request(server)
      .post(`/api/v1/trips/${tripA}/start`)
      .set(driver.auth)
      .send({ otp })
      .expect(200);
    // The last fix the server gets is at the drop-off (on-trip: not pooled).
    await location.ingest(driver.id, { lat: dropoff.lat, lng: dropoff.lng, heading: 45, speed: 8 });
    await request(server).post(`/api/v1/trips/${tripA}/complete`).set(driver.auth).expect(200);

    // Back in the pool at the drop-off immediately — no ping in between.
    const pos = await redis.client.geopos(RedisKeys.driversGeo('economy'), driver.id);
    expect(pos[0]).not.toBeNull();
    expect(Number(pos[0]![1])).toBeCloseTo(dropoff.lat, 3);
    expect(await redis.client.get(RedisKeys.driverStatus(driver.id))).toBe('online');

    // --- Rider B books right by the drop-off; the driver hasn't rated A ---
    const b = await request(server)
      .post('/api/v1/trips')
      .set(riderB.auth)
      .send({
        pickupLat: dropoff.lat + 0.001, pickupLng: dropoff.lng + 0.001,
        dropoffLat: dropoff.lat + 0.02, dropoffLng: dropoff.lng + 0.02,
        tier: 'economy', paymentMode: 'cash',
      })
      .expect(201);
    const tripB = b.body.id as string;
    try {
      expect(await waitForOffer(driver.id, tripB)).toBe(true);
    } finally {
      await request(server)
        .post(`/api/v1/trips/${tripB}/cancel`)
        .set(riderB.auth)
        .send({ reason: 'e2e' });
      await redis.client.set(RedisKeys.dispatchResponse(tripB), `0:${driver.id}`, 'PX', 30000);
      await redis.client.zrem(RedisKeys.driversGeo('economy'), driver.id);
      await redis.client.del(
        RedisKeys.driverStatus(driver.id),
        RedisKeys.driverOfferLock(driver.id),
        RedisKeys.driverLoc(driver.id),
        RedisKeys.driverTier(driver.id),
      );
    }
  }, 45_000);
});
