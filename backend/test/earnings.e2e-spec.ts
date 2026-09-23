import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';

/** The driver's "today's earnings": their share, not the fare. */
describe('Driver earnings (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  const userIds: string[] = [];

  const login = async () => {
    const phone = `+1997${Math.floor(1e6 + Math.random() * 8e6)}`;
    await redis.del(`otp:rate:${phone}`);
    const r1 = await request(server).post('/api/v1/auth/otp/request').send({ phone });
    const r2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone, code: r1.body.devCode });
    userIds.push(r2.body.user.id);
    return { id: r2.body.user.id as string, auth: { Authorization: `Bearer ${r2.body.accessToken}` } };
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
  });

  afterAll(async () => {
    await prisma.trip.deleteMany({ where: { riderId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  const ride = async (
    riderId: string,
    driverId: string,
    opts: { completedAt?: Date; status?: string; payment?: object; tripStatus?: string },
  ) =>
    prisma.trip.create({
      data: {
        riderId,
        driverId,
        status: (opts.tripStatus ?? 'completed') as never,
        pickupLat: 41.31,
        pickupLng: 69.24,
        dropoffLat: 41.33,
        dropoffLng: 69.28,
        fareFinal: 10,
        completedAt: opts.completedAt ?? new Date(),
        payment: opts.payment ? { create: opts.payment as never } : undefined,
      },
    });

  it("counts the driver's share and tips — never the platform's cut", async () => {
    const rider = await login();
    const driver = await login();
    // Card ride: fare 10, platform 2, driver 8 — then the rider tips 1.5
    // through the real endpoint, which folds the tip into driverPayout. A
    // tip counted once from `tip` and again inside driverPayout shows here.
    const tipped = await ride(rider.id, driver.id, {
      payment: { amount: 10, status: 'captured', platformFee: 2, driverPayout: 8 },
    });
    await request(server)
      .post(`/api/v1/payments/${tipped.id}/tip`)
      .set(rider.auth)
      .send({ amount: 1.5 })
      .expect(200);
    // Cash ride: the driver holds the fare but earned only their share.
    await ride(rider.id, driver.id, {
      payment: { amount: 10, method: 'cash', status: 'collected', platformFee: 2, driverPayout: 8 },
    });
    // A failed capture earned nothing.
    await ride(rider.id, driver.id, {
      payment: { amount: 10, status: 'failed', platformFee: 2, driverPayout: 8 },
    });
    // Cancellation fee: the driver's compensation counts.
    await ride(rider.id, driver.id, {
      tripStatus: 'cancelled',
      payment: { amount: 5, kind: 'cancellation', status: 'captured', platformFee: 1, driverPayout: 4 },
    });
    // Completed before today (Tashkent) — not today's.
    await ride(rider.id, driver.id, {
      completedAt: new Date(Date.now() - 2 * 86400_000),
      payment: { amount: 10, status: 'captured', platformFee: 2, driverPayout: 8 },
    });

    const today = await request(server)
      .get('/api/v1/drivers/me/earnings?range=today')
      .set(driver.auth)
      .expect(200);
    expect(today.body.total).toBe(8 + 1.5 + 8 + 4);
    expect(today.body.trips).toBe(3);

    const week = await request(server)
      .get('/api/v1/drivers/me/earnings?range=week')
      .set(driver.auth)
      .expect(200);
    expect(week.body.total).toBe(8 + 1.5 + 8 + 4 + 8);
  });

  it("never counts another driver's rides", async () => {
    const rider = await login();
    const other = await login();
    const me = await login();
    await ride(rider.id, other.id, {
      payment: { amount: 10, status: 'captured', platformFee: 2, driverPayout: 8 },
    });
    const res = await request(server).get('/api/v1/drivers/me/earnings').set(me.auth).expect(200);
    expect(res.body).toMatchObject({ total: 0, trips: 0 });
  });
});
