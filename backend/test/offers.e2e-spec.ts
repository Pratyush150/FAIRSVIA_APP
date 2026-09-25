import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';

/** Rider Offers page: GET /promos/available lists only usable, listed codes. */
describe('Offers (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  const userIds: string[] = [];
  const tag = `${Date.now() % 1e6}`;
  const codes = {
    live: `OFLIVE${tag}`,
    unlisted: `OFHIDE${tag}`,
    expired: `OFOLD${tag}`,
    full: `OFFULL${tag}`,
    inactive: `OFOFF${tag}`,
    admin: `OFADM${tag}`,
  };

  const login = async (role?: 'admin') => {
    const phone = `+1996${Math.floor(1e6 + Math.random() * 8e6)}`;
    const otp = async () => {
      await redis.del(`otp:rate:${phone}`);
      const r1 = await request(server).post('/api/v1/auth/otp/request').send({ phone });
      return request(server).post('/api/v1/auth/otp/verify').send({ phone, code: r1.body.devCode });
    };
    let r = await otp();
    userIds.push(r.body.user.id);
    if (role) {
      await prisma.user.update({ where: { id: r.body.user.id }, data: { role } });
      r = await otp();
    }
    return { id: r.body.user.id as string, auth: { Authorization: `Bearer ${r.body.accessToken}` } };
  };

  const mine = async (auth: Record<string, string>) => {
    const res = await request(server).get('/api/v1/promos/available').set(auth).expect(200);
    const ours = new Set(Object.values(codes));
    return (res.body as { code: string }[]).filter((p) => ours.has(p.code)) as Array<
      Record<string, unknown> & { code: string }
    >;
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
    const future = new Date(Date.now() + 7 * 864e5);
    await prisma.promoCode.createMany({
      data: [
        { code: codes.live, kind: 'percent', value: 50, maxDiscount: 100, minSubtotal: 50,
          perUserLimit: 2, listed: true, title: 'Welcome', description: 'Half off', expiresAt: future },
        { code: codes.unlisted, value: 10, listed: false },
        { code: codes.expired, value: 10, listed: true, expiresAt: new Date(Date.now() - 1000) },
        { code: codes.full, value: 10, listed: true, usageLimit: 1, usedCount: 1 },
        { code: codes.inactive, value: 10, listed: true, active: false },
      ],
    });
  });

  afterAll(async () => {
    await prisma.promoCode.deleteMany({ where: { code: { in: Object.values(codes) } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  it('requires a login', async () => {
    await request(server).get('/api/v1/promos/available').expect(401);
  });

  it('lists only listed, active, unexpired, not-exhausted codes with rider fields', async () => {
    const rider = await login();
    const list = await mine(rider.auth);
    expect(list.map((p) => p.code)).toEqual([codes.live]);
    expect(list[0]).toEqual({
      code: codes.live,
      title: 'Welcome',
      description: 'Half off',
      kind: 'percent',
      value: 50,
      maxDiscount: 100,
      minFare: 50,
      expiresAt: expect.any(String),
      usesLeftForMe: 2,
    });
  });

  it('counts down per rider and drops the code once that rider has used it up', async () => {
    const rider = await login();
    const other = await login();
    const promo = await prisma.promoCode.findUniqueOrThrow({ where: { code: codes.live } });
    await prisma.promoRedemption.create({
      data: { promoId: promo.id, userId: rider.id, discount: 10 },
    });
    expect((await mine(rider.auth))[0].usesLeftForMe).toBe(1);
    await prisma.promoRedemption.create({
      data: { promoId: promo.id, userId: rider.id, discount: 10 },
    });
    expect(await mine(rider.auth)).toEqual([]);
    // Another rider is unaffected.
    expect((await mine(other.auth))[0].usesLeftForMe).toBe(2);
  });

  it('admin can create and later list/unlist a code with rider-facing copy', async () => {
    const admin = await login('admin');
    const rider = await login();
    await request(server)
      .post('/api/v1/admin/promos')
      .set(admin.auth)
      .send({ code: codes.admin, kind: 'flat', value: 30, title: 'Thirty off', description: 'Any ride', listed: true })
      .expect(201);
    let list = await mine(rider.auth);
    expect(list.find((p) => p.code === codes.admin)?.title).toBe('Thirty off');
    await request(server)
      .patch(`/api/v1/admin/promos/${codes.admin}`)
      .set(admin.auth)
      .send({ listed: false })
      .expect(200);
    list = await mine(rider.auth);
    expect(list.find((p) => p.code === codes.admin)).toBeUndefined();
    // Unlisted still works when typed.
    await request(server)
      .post('/api/v1/promos/quote')
      .set(rider.auth)
      .send({ code: codes.admin, subtotal: 100 })
      .expect(200);
  });
});
