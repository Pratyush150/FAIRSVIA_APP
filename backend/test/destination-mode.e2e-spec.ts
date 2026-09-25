import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';
import { RedisKeys } from '../src/common/redis/redis.keys';
import {
  DestinationKeys,
  DestinationModeService,
} from '../src/drivers/destination/destination-mode.service';
import { DESTINATION_MAX_ACTIVE_MS } from '../src/drivers/destination/destination.rules';

/**
 * Destination ("go home") mode against the real Redis + HTTP stack:
 * endpoints, the uses-per-day limit, auto-off, and the dispatch filter the
 * sweep calls (only trips whose drop-off brings the driver closer).
 */
describe('Destination mode (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  let dest: DestinationModeService;
  const userIds: string[] = [];

  const DRIVER = { lat: 41.3, lng: 69.24 };
  const HOME = { lat: 41.39, lng: 69.24, label: 'Home' };

  const driver = async () => {
    const phone = `+1995${Math.floor(1e6 + Math.random() * 8e6)}`;
    await redis.del(`otp:rate:${phone}`);
    const r1 = await request(server).post('/api/v1/auth/otp/request').send({ phone });
    const r2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone, code: r1.body.devCode });
    const id = r2.body.user.id as string;
    userIds.push(id);
    await prisma.driverProfile.create({ data: { userId: id, licenseNo: 'DL0420110012345' } });
    await redis.client.hset(RedisKeys.driverLoc(id), { ...DRIVER, ts: Date.now() });
    return { id, auth: { Authorization: `Bearer ${r2.body.accessToken}` } };
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
    dest = app.get(DestinationModeService);
  });

  afterAll(async () => {
    for (const id of userIds) {
      const keys = await redis.client.keys(`driver:${id}:*`);
      if (keys.length) await redis.client.del(...keys);
    }
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  it('set / get / cancel; only closer trips pass the dispatch filter', async () => {
    const d = await driver();
    const other = await driver();
    const off = await request(server).get('/api/v1/drivers/me/destination-mode').set(d.auth).expect(200);
    expect(off.body).toMatchObject({ active: false, usesToday: 0, usesPerDay: 2 });

    const on = await request(server)
      .post('/api/v1/drivers/me/destination-mode')
      .set(d.auth)
      .send({ ...HOME, saveAsHome: true })
      .expect(200);
    expect(on.body).toMatchObject({ active: true, usesToday: 1, destination: { label: 'Home' } });
    expect(on.body.home).toMatchObject({ lat: HOME.lat, lng: HOME.lng });

    const toward = { dropoffLat: 41.36, dropoffLng: 69.24 };
    const away = { dropoffLat: 41.22, dropoffLng: 69.24 };
    expect(await dest.filterCandidates(toward, [d.id, other.id])).toEqual([d.id, other.id]);
    expect(await dest.filterCandidates(away, [d.id, other.id])).toEqual([other.id]);

    const cancelled = await request(server)
      .delete('/api/v1/drivers/me/destination-mode')
      .set(d.auth)
      .expect(200);
    expect(cancelled.body.active).toBe(false);
    expect(await dest.filterCandidates(away, [d.id])).toEqual([d.id]);
  });

  it('enforces uses per day (2), refusing the third with a code', async () => {
    const d = await driver();
    for (let i = 0; i < 2; i++) {
      await request(server).post('/api/v1/drivers/me/destination-mode').set(d.auth).send(HOME).expect(200);
      await request(server).delete('/api/v1/drivers/me/destination-mode').set(d.auth).expect(200);
    }
    const third = await request(server)
      .post('/api/v1/drivers/me/destination-mode')
      .set(d.auth)
      .send(HOME)
      .expect(400);
    expect(third.body.code).toBe('DESTINATION_LIMIT_REACHED');
  });

  it('auto-off within 500 m of the destination and after 2 h', async () => {
    const d = await driver();
    await request(server).post('/api/v1/drivers/me/destination-mode').set(d.auth).send(HOME).expect(200);
    await redis.client.hset(RedisKeys.driverLoc(d.id), { lat: HOME.lat - 0.002, lng: HOME.lng });
    const arrived = await request(server).get('/api/v1/drivers/me/destination-mode').set(d.auth).expect(200);
    expect(arrived.body).toMatchObject({ active: false, endedReason: 'arrived' });

    await redis.client.hset(RedisKeys.driverLoc(d.id), DRIVER);
    await request(server).post('/api/v1/drivers/me/destination-mode').set(d.auth).send(HOME).expect(200);
    await redis.client.hset(DestinationKeys.active(d.id), {
      startedAt: Date.now() - DESTINATION_MAX_ACTIVE_MS - 1000,
    });
    const expired = await request(server).get('/api/v1/drivers/me/destination-mode').set(d.auth).expect(200);
    expect(expired.body).toMatchObject({ active: false, endedReason: 'expired' });
  });

  it('validates the body', async () => {
    const d = await driver();
    await request(server)
      .post('/api/v1/drivers/me/destination-mode')
      .set(d.auth)
      .send({ lat: 200, lng: 69 })
      .expect(400);
  });
});
