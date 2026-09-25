import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';
import { RedisKeys } from '../src/common/redis/redis.keys';
import { DispatchService } from '../src/dispatch/dispatch.service';
import { RealtimeService } from '../src/realtime/realtime.service';

/**
 * Pilot calling: the rider's "Call" dials the driver, the driver's "Call
 * rider" dials the rider. Both numbers are real (users.phone) in the pilot —
 * production must mask them — so they go only to the other party, and only
 * while the ride is live.
 */
describe('Rider and driver can call each other (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  let emit: jest.SpyInstance;
  const userIds: string[] = [];

  const login = async () => {
    const phone = `+1997${Math.floor(1e6 + Math.random() * 8e6)}`;
    await redis.del(`otp:rate:${phone}`);
    const r1 = await request(server).post('/api/v1/auth/otp/request').send({ phone });
    const r2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone, code: r1.body.devCode });
    userIds.push(r2.body.user.id);
    return {
      id: r2.body.user.id as string,
      phone,
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

  afterAll(async () => {
    for (const id of userIds) {
      await redis.client.del(
        RedisKeys.driverActiveTrip(id),
        RedisKeys.driverActiveRider(id),
        RedisKeys.driverStatus(id),
      );
    }
    await prisma.trip.deleteMany({ where: { riderId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  const tripWith = (riderId: string, driverId: string | null, status: string) =>
    prisma.trip.create({
      data: {
        riderId,
        driverId,
        status: status as never,
        pickupLat: 41.31,
        pickupLng: 69.24,
        dropoffLat: 41.33,
        dropoffLng: 69.28,
      },
    });

  it('trip:accepted gives the rider the driver phone', async () => {
    const rider = await login();
    const driver = await login();
    const trip = await tripWith(rider.id, null, 'matching');
    emit.mockClear();

    const assign = (app.get(DispatchService) as unknown as {
      assign: (t: unknown, d: string) => Promise<boolean>;
    }).assign.bind(app.get(DispatchService));
    await expect(assign(trip, driver.id)).resolves.toBe(true);

    const call = emit.mock.calls.find((c) => c[1] === 'trip:accepted');
    expect(call).toBeDefined();
    expect(call![0]).toBe(rider.id);
    expect(call![2].driver).toEqual(
      expect.objectContaining({ id: driver.id, phone: driver.phone }),
    );
  });

  it('GET /trips/:id and /trips/active carry the other party phone while live', async () => {
    const rider = await login();
    const driver = await login();
    const trip = await tripWith(rider.id, driver.id, 'arrived');

    const asRider = await request(server)
      .get(`/api/v1/trips/${trip.id}`)
      .set(rider.auth)
      .expect(200);
    expect(asRider.body.driver.phone).toBe(driver.phone);
    expect(asRider.body.rider).toBeUndefined();

    const asDriver = await request(server)
      .get(`/api/v1/trips/${trip.id}`)
      .set(driver.auth)
      .expect(200);
    expect(asDriver.body.rider).toEqual(
      expect.objectContaining({ id: rider.id, phone: rider.phone }),
    );
    // The rider's rating rides along for the in-trip rider card ("★ 5.0").
    expect(typeof asDriver.body.rider.rating).toBe('number');

    const active = await request(server)
      .get('/api/v1/trips/active')
      .set(driver.auth)
      .expect(200);
    expect(active.body.rider.phone).toBe(rider.phone);
  });

  it('a finished trip exposes neither number', async () => {
    const rider = await login();
    const driver = await login();
    const trip = await tripWith(rider.id, driver.id, 'completed');

    const asRider = await request(server)
      .get(`/api/v1/trips/${trip.id}`)
      .set(rider.auth)
      .expect(200);
    expect(asRider.body.driver.phone).toBeUndefined();

    const asDriver = await request(server)
      .get(`/api/v1/trips/${trip.id}`)
      .set(driver.auth)
      .expect(200);
    expect(asDriver.body.rider).toBeUndefined();
  });
});
