import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';
import { RedisKeys } from '../src/common/redis/redis.keys';
import { RealtimeService } from '../src/realtime/realtime.service';
import { FatigueKeys } from '../src/drivers/fatigue/fatigue.rules';
import { FatigueService } from '../src/drivers/fatigue/fatigue.service';
import { FatigueSweeper } from '../src/drivers/fatigue/fatigue.sweeper';

/**
 * Fatigue limit (Uber rule): 12 h online, reset only by a 6 h offline break.
 * Accumulated time is seeded straight into Redis so the test does not need
 * to wait 12 hours.
 */
describe('Driver fatigue limit (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  let sweeper: FatigueSweeper;
  let fatigue: FatigueService;
  let emit: jest.SpyInstance;
  const userIds: string[] = [];
  const H = 3600;

  const driver = async () => {
    const phone = `+1997${Math.floor(1e6 + Math.random() * 8e6)}`;
    await redis.del(`otp:rate:${phone}`);
    const r1 = await request(server).post('/api/v1/auth/otp/request').send({ phone });
    const r2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone, code: r1.body.devCode });
    const id = r2.body.user.id as string;
    userIds.push(id);
    await prisma.user.update({ where: { id }, data: { fullName: 'Fatigue Tester', role: 'driver' } });
    await prisma.driverProfile.create({
      data: { userId: id, licenseNo: 'DL0420110012345', docsVerified: true, plateNumber: '01A123BC' },
    });
    return { id, auth: { Authorization: `Bearer ${r2.body.accessToken}` } };
  };
  const seed = (id: string, accSecs: number, lastOffAgoSecs: number | null) =>
    redis.client.hset(FatigueKeys.fatigue(id), {
      acc: accSecs,
      ...(lastOffAgoSecs === null ? {} : { lastOff: Date.now() - lastOffAgoSecs * 1000 }),
    });
  const goOnline = (auth: Record<string, string>) =>
    request(server).post('/api/v1/drivers/status').set(auth).send({ status: 'online' });

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api/v1', { exclude: [{ path: 'metrics', method: RequestMethod.GET }] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
    await app.init();
    server = app.getHttpServer();
    prisma = app.get(PrismaService);
    redis = app.get(RedisService);
    sweeper = app.get(FatigueSweeper);
    fatigue = app.get(FatigueService);
    emit = jest.spyOn(app.get(RealtimeService), 'emitToUser');
  });

  afterAll(async () => {
    for (const id of userIds) {
      await redis.client.del(FatigueKeys.fatigue(id), RedisKeys.driverOnlineSince(id), RedisKeys.driverStatus(id));
      await redis.client.srem(FatigueKeys.fatigueTracked(), id);
    }
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  const eventsFor = (id: string) =>
    emit.mock.calls.filter((c) => c[0] === id).map((c) => c[1] as string);

  it('GET /drivers/me/fatigue reports online time against the 12 h limit', async () => {
    const d = await driver();
    await seed(d.id, 9 * H + 40 * 60, 60);
    const r = await request(server).get('/api/v1/drivers/me/fatigue').set(d.auth).expect(200);
    expect(r.body).toMatchObject({
      onlineSeconds: 9 * H + 40 * 60,
      limitSeconds: 12 * H,
      remainingSeconds: 2 * H + 20 * 60,
      overLimit: false,
      resting: false,
    });
  });

  it('refuses going online with 409 DRIVER_REST_REQUIRED and the time left', async () => {
    const d = await driver();
    await seed(d.id, 12 * H, 2 * H); // hit the limit, offline 2 h of the 6 h break
    const r = await goOnline(d.auth).expect(409);
    expect(r.body.code).toBe('DRIVER_REST_REQUIRED');
    expect(r.body.restSecondsLeft).toBeGreaterThan(4 * H - 10);
    expect(r.body.restSecondsLeft).toBeLessThanOrEqual(4 * H);
    expect(typeof r.body.restUntil).toBe('string');
    expect(await redis.client.get(RedisKeys.driverStatus(d.id))).not.toBe('online');
    const s = await request(server).get('/api/v1/drivers/me/fatigue').set(d.auth).expect(200);
    expect(s.body.resting).toBe(true);
  });

  it('a short break does not reset the count; a full 6 h break does', async () => {
    const d = await driver();
    await seed(d.id, 11 * H, 7 * H);
    await goOnline(d.auth).expect(200);
    expect(await redis.client.hget(FatigueKeys.fatigue(d.id), 'acc')).toBe('0');
    await request(server).post('/api/v1/drivers/status').set(d.auth).send({ status: 'offline' }).expect(200);

    const e = await driver();
    await seed(e.id, 11 * H, 30 * 60);
    await goOnline(e.auth).expect(200);
    const s = await fatigue.state(e.id);
    expect(s.onlineSeconds).toBeGreaterThanOrEqual(11 * H);
    await request(server).post('/api/v1/drivers/status').set(e.auth).send({ status: 'offline' }).expect(200);
    // the session was credited to the counter and lastOff moved to now
    expect(Number(await redis.client.hget(FatigueKeys.fatigue(e.id), 'acc'))).toBeGreaterThanOrEqual(11 * H);
  });

  it('warns once 30 min before the limit (socket event)', async () => {
    const d = await driver();
    await seed(d.id, 11 * H + 40 * 60, 60);
    await goOnline(d.auth).expect(200);
    const done = await sweeper.tick(Date.now(), false);
    expect(done[d.id]).toBe('warned');
    expect(eventsFor(d.id)).toContain('driver:fatigue_warning');
    const again = await sweeper.tick(Date.now(), false);
    expect(again[d.id]).toBe('ok');
  });

  it('over the limit: no offers, forced offline, then locked out', async () => {
    const d = await driver();
    await seed(d.id, 11 * H + 59 * 60, 60);
    await goOnline(d.auth).expect(200);
    expect(await fatigue.canTakeOffers(d.id)).toBe(true);
    // one simulated minute later the limit is reached
    const later = Date.now() + 61_000;
    expect(await fatigue.canTakeOffers(d.id, later)).toBe(false);

    // mid-trip: the sweeper waits
    await redis.client.set(RedisKeys.driverActiveTrip(d.id), 'some-trip');
    expect((await sweeper.tick(later, false))[d.id]).toBe('over_limit_on_trip');
    expect(await redis.client.get(RedisKeys.driverStatus(d.id))).toBe('online');
    await redis.client.del(RedisKeys.driverActiveTrip(d.id));

    // trip over: forced offline and told why
    expect((await sweeper.tick(later, false))[d.id]).toBe('forced_offline');
    expect(await redis.client.get(RedisKeys.driverStatus(d.id))).toBe('offline');
    const statusEvent = emit.mock.calls.find(
      (c) => c[0] === d.id && c[1] === 'driver:status_changed',
    );
    expect(statusEvent?.[2]).toEqual({ status: 'offline', reason: 'fatigue' });
    expect(eventsFor(d.id)).toContain('driver:fatigue_locked');

    // Going online is refused. (The real session ended at wall-clock time, so
    // bump the counter over the limit as the simulated minute would have.)
    await redis.client.hset(FatigueKeys.fatigue(d.id), { acc: 12 * H });
    const r = await goOnline(d.auth).expect(409);
    expect(r.body.code).toBe('DRIVER_REST_REQUIRED');
  });
});
