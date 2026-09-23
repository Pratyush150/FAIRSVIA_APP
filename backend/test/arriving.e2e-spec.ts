import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';
import { RealtimeService } from '../src/realtime/realtime.service';

/** The driver-arriving screen's server side. */
describe('Arriving screen (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  let emit: jest.SpyInstance;
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

  // app.close() drains in-flight BullMQ jobs; see app.e2e-spec.ts.
  afterAll(async () => {
    await prisma.trip.deleteMany({ where: { riderId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  const tripWith = async (riderId: string, driverId: string, status: string) =>
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

  describe("I'm on my way", () => {
    it('tells the waiting driver once, and ignores repeat taps', async () => {
      const rider = await login();
      const driver = await login();
      const trip = await tripWith(rider.id, driver.id, 'arrived');
      emit.mockClear();

      const first = await request(server)
        .post(`/api/v1/trips/${trip.id}/on-my-way`)
        .set(rider.auth)
        .expect(200);
      expect(first.body).toEqual({ ok: true, driverNotified: true });
      expect(emit).toHaveBeenCalledWith(
        driver.id,
        'trip:rider_coming',
        expect.objectContaining({ tripId: trip.id }),
      );

      emit.mockClear();
      const again = await request(server)
        .post(`/api/v1/trips/${trip.id}/on-my-way`)
        .set(rider.auth)
        .expect(200);
      expect(again.body.driverNotified).toBe(false);
      expect(emit).not.toHaveBeenCalledWith(driver.id, 'trip:rider_coming', expect.anything());

      const events = await prisma.tripEvent.findMany({ where: { tripId: trip.id } });
      expect(events.filter((e) => (e.meta as { event?: string })?.event === 'rider_coming')).toHaveLength(1);
    });

    it('only while the driver is coming or waiting, and only for the rider', async () => {
      const rider = await login();
      const driver = await login();
      const onTrip = await tripWith(rider.id, driver.id, 'in_progress');
      await request(server).post(`/api/v1/trips/${onTrip.id}/on-my-way`).set(rider.auth).expect(400);

      const waiting = await tripWith((await login()).id, driver.id, 'accepted');
      await request(server).post(`/api/v1/trips/${waiting.id}/on-my-way`).set(rider.auth).expect(403);
    });
  });
});
