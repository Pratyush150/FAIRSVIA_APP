import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';

/**
 * Driver tools taken from the competitor benchmark
 * (docs/plans/driver-app-benchmark.md): the rider no-show cancel that pays the
 * driver the cancellation fee, the busy-areas demand map, and the earnings
 * dashboard's daily series / trip list.
 */
describe('Driver tools (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  const userIds: string[] = [];

  const login = async () => {
    const phone = `+1996${Math.floor(1e6 + Math.random() * 8e6)}`;
    await redis.del(`otp:rate:${phone}`);
    const r1 = await request(server).post('/api/v1/auth/otp/request').send({ phone });
    const r2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone, code: r1.body.devCode });
    userIds.push(r2.body.user.id);
    return { id: r2.body.user.id as string, auth: { Authorization: `Bearer ${r2.body.accessToken}` } };
  };

  const driver = async () => {
    const d = await login();
    await prisma.driverProfile.create({ data: { userId: d.id, licenseNo: 'DL0420110012345' } });
    return d;
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

  describe('rider no-show', () => {
    const arrivedTrip = (riderId: string, driverId: string, arrivedAgoSec: number) =>
      prisma.trip.create({
        data: {
          riderId,
          driverId,
          status: 'arrived',
          pickupLat: 18.52,
          pickupLng: 73.86,
          dropoffLat: 18.55,
          dropoffLng: 73.9,
          fareEstimate: 200,
          paymentMode: 'cash',
          acceptedAt: new Date(Date.now() - (arrivedAgoSec + 300) * 1000),
          arrivedAt: new Date(Date.now() - arrivedAgoSec * 1000),
        },
      });

    it('refuses a no-show before the wait is up, with the seconds left', async () => {
      const rider = await login();
      const d = await driver();
      const trip = await arrivedTrip(rider.id, d.id, 60);
      const res = await request(server)
        .post(`/api/v1/trips/${trip.id}/driver-cancel`)
        .set(d.auth)
        .send({ reason: "Rider didn't show up", noShow: true })
        .expect(400);
      expect(res.body.code).toBe('NO_SHOW_TOO_EARLY');
      expect(res.body.secondsLeft).toBeGreaterThan(200);
      expect(res.body.secondsLeft).toBeLessThanOrEqual(240);
      const still = await prisma.trip.findUnique({ where: { id: trip.id } });
      expect(still?.status).toBe('arrived');
    });

    it('after the wait: cancels, charges the rider the fee and books the driver share', async () => {
      const rider = await login();
      const d = await driver();
      const trip = await arrivedTrip(rider.id, d.id, 6 * 60);
      const res = await request(server)
        .post(`/api/v1/trips/${trip.id}/driver-cancel`)
        .set(d.auth)
        .send({ reason: "Rider didn't show up", noShow: true })
        .expect(200);
      expect(res.body.status).toBe('cancelled');
      expect(res.body.fee).toBeGreaterThan(0);
      const pay = await prisma.payment.findUnique({ where: { tripId: trip.id } });
      expect(pay?.kind).toBe('cancellation');
      expect(Number(pay?.amount)).toBe(res.body.fee);
      expect(Number(pay?.driverPayout)).toBeGreaterThan(0);
      const t = await prisma.trip.findUnique({ where: { id: trip.id } });
      expect(t?.cancelledBy).toBe('driver');
    });

    it('a no-show needs the driver to be at the pickup (accepted is not enough)', async () => {
      const rider = await login();
      const d = await driver();
      const trip = await prisma.trip.create({
        data: {
          riderId: rider.id,
          driverId: d.id,
          status: 'accepted',
          pickupLat: 18.52,
          pickupLng: 73.86,
          dropoffLat: 18.55,
          dropoffLng: 73.9,
          acceptedAt: new Date(Date.now() - 20 * 60_000),
        },
      });
      const res = await request(server)
        .post(`/api/v1/trips/${trip.id}/driver-cancel`)
        .set(d.auth)
        .send({ reason: "Rider didn't show up", noShow: true })
        .expect(400);
      expect(res.body.code).toBe('NO_SHOW_NOT_ARRIVED');
    });

    it('a plain driver cancel still charges nobody', async () => {
      const rider = await login();
      const d = await driver();
      const trip = await arrivedTrip(rider.id, d.id, 6 * 60);
      const res = await request(server)
        .post(`/api/v1/trips/${trip.id}/driver-cancel`)
        .set(d.auth)
        .send({ reason: 'Car trouble' })
        .expect(200);
      expect(res.body.fee).toBe(0);
      expect(await prisma.payment.findUnique({ where: { tripId: trip.id } })).toBeNull();
    });
  });

  describe('busy areas', () => {
    // A spot far from any real test data so other suites can't leak in.
    const LAT = -45.87;
    const LNG = 170.5;

    it('returns recent-request cells around the driver, never a lone request', async () => {
      const rider = await login();
      const d = await driver();
      const at = (lat: number, lng: number) =>
        prisma.trip.create({
          data: {
            riderId: rider.id,
            status: 'cancelled',
            pickupLat: lat,
            pickupLng: lng,
            dropoffLat: lat + 0.02,
            dropoffLng: lng + 0.02,
          },
        });
      await at(LAT + 0.001, LNG + 0.001);
      await at(LAT - 0.001, LNG + 0.002);
      await at(LAT + 0.002, LNG - 0.001);
      await at(LAT + 0.04, LNG + 0.04); // alone in its cell
      // An hour-old request is not "recent".
      const old = await at(LAT, LNG);
      await prisma.trip.update({
        where: { id: old.id },
        data: { requestedAt: new Date(Date.now() - 3 * 3600_000) },
      });
      await redis.client.del(`demand:map:${Math.round(LAT / 0.05)}:${Math.round(LNG / 0.05)}`);

      const res = await request(server)
        .get(`/api/v1/drivers/me/demand?lat=${LAT}&lng=${LNG}`)
        .set(d.auth)
        .expect(200);
      expect(res.body.windowMinutes).toBe(60);
      expect(res.body.cells).toEqual([
        { lat: LAT, lng: LNG, count: 3, intensity: 1 },
      ]);
    });

    it('is for drivers only and validates coordinates', async () => {
      const rider = await login();
      await request(server)
        .get('/api/v1/drivers/me/demand?lat=18.5&lng=73.8')
        .set(rider.auth)
        .expect(400);
      const d = await driver();
      await request(server)
        .get('/api/v1/drivers/me/demand?lat=123&lng=73.8')
        .set(d.auth)
        .expect(400);
    });
  });

  describe('earnings dashboard', () => {
    it('returns 7 daily buckets that sum to the week, the trip list and online time', async () => {
      const rider = await login();
      const d = await driver();
      const trip = (completedAt: Date, payout: number) =>
        prisma.trip.create({
          data: {
            riderId: rider.id,
            driverId: d.id,
            status: 'completed',
            pickupLat: 18.52,
            pickupLng: 73.86,
            pickupAddr: 'FC Road',
            dropoffLat: 18.55,
            dropoffLng: 73.9,
            dropoffAddr: 'Airport',
            distanceM: 8200,
            fareFinal: 200,
            completedAt,
            payment: {
              create: { amount: 200, status: 'captured', platformFee: 200 - payout, driverPayout: payout },
            },
          },
        });
      await trip(new Date(), 160);
      await trip(new Date(Date.now() - 3 * 86400_000), 120);
      // Outside the 7 business days.
      await trip(new Date(Date.now() - 9 * 86400_000), 999);
      // An open online session of ~10 minutes.
      await redis.client.set(`driver:${d.id}:onlineSince`, String(Date.now() - 600_000));

      const week = await request(server)
        .get('/api/v1/drivers/me/earnings?range=week')
        .set(d.auth)
        .expect(200);
      expect(week.body.total).toBe(280);
      expect(week.body.trips).toBe(2);
      expect(week.body.days).toHaveLength(7);
      const sum = week.body.days.reduce((a: number, x: { total: number }) => a + x.total, 0);
      expect(sum).toBe(280);
      expect(week.body.days[6].total).toBe(160);
      expect(week.body.recentTrips).toHaveLength(2);
      expect(week.body.recentTrips[0]).toMatchObject({
        pickupAddr: 'FC Road',
        dropoffAddr: 'Airport',
        distanceM: 8200,
        earned: 160,
      });
      expect(week.body.onlineSeconds).toBeGreaterThanOrEqual(590);

      const today = await request(server)
        .get('/api/v1/drivers/me/earnings?range=today')
        .set(d.auth)
        .expect(200);
      expect(today.body.total).toBe(160);
      expect(today.body.recentTrips).toHaveLength(1);
      expect(today.body.onlineSeconds).toBeGreaterThanOrEqual(590);
      await redis.client.del(`driver:${d.id}:onlineSince`);
    });
  });
});
