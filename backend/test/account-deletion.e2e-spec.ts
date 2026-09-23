import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';
import { LedgerService } from '../src/ledger/ledger.service';

/** Self-service account deletion through the real HTTP stack. */
describe('Account deletion (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  let ledger: LedgerService;
  const userIds: string[] = [];

  const login = async (phone: string) => {
    await redis.del(`otp:rate:${phone}`);
    const r1 = await request(server).post('/api/v1/auth/otp/request').send({ phone });
    const r2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone, code: r1.body.devCode });
    expect(r2.status).toBe(200);
    userIds.push(r2.body.user.id);
    return {
      token: r2.body.accessToken as string,
      refresh: r2.body.refreshToken as string,
      id: r2.body.user.id as string,
    };
  };
  const phone = () => `+1998${Math.floor(Math.random() * 1e7)}`;
  const trip = (riderId: string, status: string, driverId?: string) =>
    prisma.trip.create({
      data: {
        riderId,
        driverId,
        status: status as never,
        pickupLat: 41.3,
        pickupLng: 69.24,
        dropoffLat: 41.31,
        dropoffLng: 69.25,
      },
    });

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api/v1', {
      exclude: [{ path: 'metrics', method: RequestMethod.GET }],
    });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer();
    prisma = app.get(PrismaService);
    redis = app.get(RedisService);
    ledger = app.get(LedgerService);
  });

  // app.close() drains in-flight BullMQ jobs (graceful shutdown). A dispatch
  // job can be mid-offer when the suite ends, so the default 5 s hook limit
  // intermittently failed the suite with every test green.
  afterAll(async () => {
    await prisma.ledgerEntry.deleteMany({ where: { driverId: { in: userIds } } });
    await prisma.trip.deleteMany({ where: { riderId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  it('removes personal data, keeps trip records, and revokes access', async () => {
    const p = phone();
    const rider = await login(p);
    const auth = { Authorization: `Bearer ${rider.token}` };
    await request(server)
      .post('/api/v1/users/me/places')
      .set(auth)
      .send({ label: 'Home', lat: 41.3, lng: 69.24, address: 'Tashkent' })
      .expect(201);
    await request(server).patch('/api/v1/users/me').set(auth).send({ fullName: 'Aziz Karimov' }).expect(200);
    const done = await trip(rider.id, 'completed');
    const scheduled = await trip(rider.id, 'scheduled');

    const res = await request(server).delete('/api/v1/users/me').set(auth);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ deleted: true });

    const row = await prisma.user.findUnique({ where: { id: rider.id } });
    expect(row?.fullName).toBeNull();
    expect(row?.phone).not.toBe(p);
    expect(row?.isActive).toBe(false);
    expect(row?.deletedAt).not.toBeNull();
    expect(await prisma.savedPlace.count({ where: { userId: rider.id } })).toBe(0);
    expect(await prisma.refreshToken.count({ where: { userId: rider.id } })).toBe(0);
    // Legal records stay; the future ride does not happen.
    expect((await prisma.trip.findUnique({ where: { id: done.id } }))?.status).toBe('completed');
    expect((await prisma.trip.findUnique({ where: { id: scheduled.id } }))?.status).toBe('cancelled');

    // The old session is dead on both tokens.
    await request(server).get('/api/v1/users/me').set(auth).expect(401);
    const refreshed = await request(server)
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: rider.refresh });
    expect(refreshed.status).toBeGreaterThanOrEqual(400);

    // The same number can sign up again — as a brand-new, empty account.
    const again = await login(p);
    expect(again.id).not.toBe(rider.id);
    const places = await request(server)
      .get('/api/v1/users/me/places')
      .set({ Authorization: `Bearer ${again.token}` })
      .expect(200);
    expect(places.body).toEqual([]);
  });

  it('refuses while a ride is in progress', async () => {
    const rider = await login(phone());
    await trip(rider.id, 'in_progress');
    const res = await request(server)
      .delete('/api/v1/users/me')
      .set({ Authorization: `Bearer ${rider.token}` });
    expect(res.status).toBe(409);
    expect(res.body.message).toMatch(/ride in progress/);
    expect((await prisma.user.findUnique({ where: { id: rider.id } }))?.deletedAt).toBeNull();
  });

  it('refuses a driver with unwithdrawn earnings, then allows it at zero', async () => {
    const driver = await login(phone());
    await prisma.user.update({ where: { id: driver.id }, data: { role: 'driver' } });
    await prisma.driverProfile.create({ data: { userId: driver.id, licenseNo: 'AB1234567' } });
    await ledger.record(driver.id, 'earning', 25, { note: 'seed' });
    const auth = { Authorization: `Bearer ${driver.token}` };

    const blocked = await request(server).delete('/api/v1/users/me').set(auth);
    expect(blocked.status).toBe(409);
    expect(blocked.body.message).toMatch(/Withdraw them first/);

    await ledger.withdraw(driver.id, 25);
    await request(server).delete('/api/v1/users/me').set(auth).expect(200);
    const profile = await prisma.driverProfile.findUnique({ where: { userId: driver.id } });
    expect(profile?.licenseNo).toBeNull();
    await prisma.driverProfile.delete({ where: { userId: driver.id } });
  });
});
