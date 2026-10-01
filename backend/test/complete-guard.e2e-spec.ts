import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisKeys } from '../src/common/redis/redis.keys';
import { RedisService } from '../src/common/redis/redis.service';
import { PricingService } from '../src/pricing/pricing.service';
import { LocationService } from '../src/location/location.service';
import { RealtimeService } from '../src/realtime/realtime.service';

/**
 * Audit 2026-09-25 (#4): a driver tapped Complete at the pickup and a 0 m /
 * 11 s trip was charged 100% of the estimate. Owner rule: Complete ends the
 * trip wherever the driver taps — but short of the drop-off it is charged
 * max(minimum fare, metered), never the estimate. The rider (or driver) can
 * also end a started ride via POST /trips/:id/end-early, same fare rule.
 */
describe('Complete anywhere + early end (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  let location: LocationService;
  let pricing: PricingService;
  let emit: jest.SpyInstance;
  const userIds: string[] = [];

  const login = async () => {
    const phone = `+1995${Math.floor(1e6 + Math.random() * 8e6)}`;
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

  const waitForOffer = async (driverId: string, tripId: string) => {
    for (let i = 0; i < 100; i++) {
      const hit = emit.mock.calls.some(
        ([u, e, d]) => u === driverId && e === 'trip:offer' && d?.tripId === tripId,
      );
      if (hit) return true;
      await new Promise((r) => setTimeout(r, 100));
    }
    return false;
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
    pricing = app.get(PricingService);
    emit = jest.spyOn(app.get(RealtimeService), 'emitToUser');
  });

  afterAll(async () => {
    await prisma.trip.deleteMany({ where: { riderId: { in: userIds } } });
    await prisma.driverProfile.deleteMany({ where: { userId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  it('Complete at the pickup ends the trip at the minimum/metered fare, not the estimate', async () => {
    const base = { lat: 6.2 + Math.random() * 0.3, lng: 3.1 + Math.random() * 0.3 };
    const dropoff = { lat: base.lat + 0.05, lng: base.lng + 0.05 }; // ~7.8 km away

    const driver = await login();
    await request(server).patch('/api/v1/users/me').set(driver.auth)
      .send({ fullName: 'Guard Driver' }).expect(200);
    await request(server).post('/api/v1/drivers/onboarding').set(driver.auth)
      .send({
        vehicleMake: 'Maruti Suzuki', vehicleModel: 'Dzire',
        plateNumber: `CGD${Date.now() % 100000}`, vehicleTier: 'economy',
      })
      .expect(201);
    await prisma.driverProfile.update({ where: { userId: driver.id }, data: { docsVerified: true } });
    await request(server).post('/api/v1/drivers/status').set(driver.auth)
      .send({ status: 'online' }).expect(200);
    await location.ingest(driver.id, { lat: base.lat, lng: base.lng, heading: 0, speed: 0 });

    const rider = await login();
    const t = await request(server).post('/api/v1/trips').set(rider.auth)
      .send({
        pickupLat: base.lat, pickupLng: base.lng,
        dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
        tier: 'economy', paymentMode: 'cash',
      })
      .expect(201);
    const tripId = t.body.id as string;
    // OSRM has no map for this remote test spot, so the routed estimate sits
    // at the tier minimum. Give it a realistic up-front price (the audit trip
    // was quoted 89) so "never the estimate" is actually distinguishable.
    await prisma.trip.update({ where: { id: tripId }, data: { fareEstimate: 289 } });
    try {
      expect(await waitForOffer(driver.id, tripId)).toBe(true);
      await request(server).post(`/api/v1/trips/${tripId}/accept`).set(driver.auth).expect(200);
      for (let i = 0; i < 50; i++) {
        if ((await redis.client.get(RedisKeys.driverActiveTrip(driver.id))) === tripId) break;
        await new Promise((r) => setTimeout(r, 100));
      }
      await request(server).post(`/api/v1/trips/${tripId}/arrived`).set(driver.auth).expect(200);
      const otp = (await prisma.trip.findUnique({ where: { id: tripId } }))!.startOtp;
      await request(server).post(`/api/v1/trips/${tripId}/start`).set(driver.auth)
        .send({ otp }).expect(200);
      // A fresh fix, still at the pickup.
      await location.ingest(driver.id, { lat: base.lat, lng: base.lng, heading: 0, speed: 0 });

      // Early end without a reason → validation error (nothing settled).
      await request(server).post(`/api/v1/trips/${tripId}/complete`).set(driver.auth)
        .send({ endEarly: true }).expect(400);
      expect((await prisma.trip.findUnique({ where: { id: tripId } }))!.status).toBe('in_progress');

      // Plain Complete at the pickup ENDS the trip (owner rule: it ends
      // wherever the driver taps) — at max(minimum fare, metered).
      const done = await request(server).post(`/api/v1/trips/${tripId}/complete`)
        .set(driver.auth).send({}).expect(200);
      const trip = (await prisma.trip.findUnique({ where: { id: tripId } }))!;
      const estimate = Number(trip.fareEstimate);
      const minFare = pricing.minFareFor('economy');
      const fareFinal = Number(trip.fareFinal);
      expect(trip.status).toBe('completed');
      expect(fareFinal).toBeGreaterThanOrEqual(minFare);
      expect(fareFinal).toBeLessThan(estimate);
      expect(Number.isInteger(fareFinal) || trip.currency === 'USD').toBe(true);
      // Metered at 0 m and a few seconds is base + booking (+ pennies of time):
      const metered = pricing.estimateForTier('economy', 0, trip.durationS ?? 0, 1).fare;
      expect(Math.abs(fareFinal - Math.max(minFare, metered))).toBeLessThanOrEqual(1);
      expect(done.body.breakdown.endedEarly).toBe(true);
      expect(['minimum', 'metered']).toContain(done.body.breakdown.fareBasis);

      // The rider receipt replays it.
      const rec = await request(server).get(`/api/v1/payments/${tripId}/receipt`)
        .set(rider.auth).expect(200);
      expect(rec.body.breakdown.endedEarly).toBe(true);
      expect(rec.body.breakdown.endedAwayFromDropoffM).toBeGreaterThan(500);
      expect(rec.body.breakdown.fareBasis).toBe(done.body.breakdown.fareBasis);
      // eslint-disable-next-line no-console
      console.log(`[complete-guard] estimate ${estimate}, min ${minFare}, charged ${fareFinal} (${done.body.breakdown.fareBasis})`);
    } finally {
      await redis.client.zrem(RedisKeys.driversGeo('economy'), driver.id);
      await redis.client.del(
        RedisKeys.driverStatus(driver.id),
        RedisKeys.driverOfferLock(driver.id),
        RedisKeys.driverLoc(driver.id),
        RedisKeys.driverTier(driver.id),
      );
    }
  }, 45_000);

  it('rider "End trip here": POST /end-early completes at the minimum/metered fare for both parties', async () => {
    const base = { lat: 7.2 + Math.random() * 0.3, lng: 4.1 + Math.random() * 0.3 };
    const dropoff = { lat: base.lat + 0.05, lng: base.lng + 0.05 };
    const driver = await login();
    await request(server).patch('/api/v1/users/me').set(driver.auth)
      .send({ fullName: 'Early Driver' }).expect(200);
    await request(server).post('/api/v1/drivers/onboarding').set(driver.auth)
      .send({
        vehicleMake: 'Maruti Suzuki', vehicleModel: 'Dzire',
        plateNumber: `EER${Date.now() % 100000}`, vehicleTier: 'economy',
      })
      .expect(201);
    await prisma.driverProfile.update({ where: { userId: driver.id }, data: { docsVerified: true } });
    await request(server).post('/api/v1/drivers/status').set(driver.auth)
      .send({ status: 'online' }).expect(200);
    await location.ingest(driver.id, { lat: base.lat, lng: base.lng, heading: 0, speed: 0 });
    const rider = await login();
    const stranger = await login();
    const t = await request(server).post('/api/v1/trips').set(rider.auth)
      .send({
        pickupLat: base.lat, pickupLng: base.lng,
        dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
        tier: 'economy', paymentMode: 'cash',
      })
      .expect(201);
    const tripId = t.body.id as string;
    await prisma.trip.update({ where: { id: tripId }, data: { fareEstimate: 289 } });
    try {
      expect(await waitForOffer(driver.id, tripId)).toBe(true);
      await request(server).post(`/api/v1/trips/${tripId}/accept`).set(driver.auth).expect(200);
      for (let i = 0; i < 50; i++) {
        if ((await redis.client.get(RedisKeys.driverActiveTrip(driver.id))) === tripId) break;
        await new Promise((r) => setTimeout(r, 100));
      }
      // Not started yet → refused.
      const early = await request(server).post(`/api/v1/trips/${tripId}/end-early`)
        .set(rider.auth).send({}).expect(400);
      expect(early.body.code).toBe('TRIP_NOT_IN_PROGRESS');
      await request(server).post(`/api/v1/trips/${tripId}/arrived`).set(driver.auth).expect(200);
      const otp = (await prisma.trip.findUnique({ where: { id: tripId } }))!.startOtp;
      await request(server).post(`/api/v1/trips/${tripId}/start`).set(driver.auth)
        .send({ otp }).expect(200);
      await location.ingest(driver.id, { lat: base.lat, lng: base.lng, heading: 0, speed: 0 });

      await request(server).post(`/api/v1/trips/${tripId}/end-early`)
        .set(stranger.auth).send({}).expect(403);
      emit.mockClear();
      const done = await request(server).post(`/api/v1/trips/${tripId}/end-early`)
        .set(rider.auth).send({}).expect(200);
      const trip = (await prisma.trip.findUnique({ where: { id: tripId } }))!;
      expect(trip.status).toBe('completed');
      expect(Number(trip.fareFinal)).toBe(Math.round(pricing.minFareFor('economy')));
      expect(done.body.breakdown).toMatchObject({
        fareBasis: 'minimum', endedEarly: true, endReason: 'Rider ended the trip',
      });
      const sentTo = emit.mock.calls
        .filter(([, e]) => e === 'trip:completed').map(([u]) => u);
      expect(sentTo).toEqual(expect.arrayContaining([rider.id, driver.id]));
      const ev = await prisma.tripEvent.findFirst({ where: { tripId, toStatus: 'completed' } });
      expect(ev?.actor).toBe('rider');
    } finally {
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
