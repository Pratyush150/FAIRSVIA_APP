import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';

/** Promotional cards under the ride: admin-managed, only live ones served. */
describe('Ride cards (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  const userIds: string[] = [];
  // Cards that existed before the suite: paused for the test (the live list
  // is global), restored after — never deleted.
  let paused: string[] = [];
  const createdCards: string[] = [];
  const promoCode = `CARD${Date.now() % 1e6}`;

  const login = async (role?: 'admin') => {
    const phone = `+1995${Math.floor(1e6 + Math.random() * 8e6)}`;
    const otp = async () => {
      await redis.del(`otp:rate:${phone}`);
      const r1 = await request(server).post('/api/v1/auth/otp/request').send({ phone });
      return request(server).post('/api/v1/auth/otp/verify').send({ phone, code: r1.body.devCode });
    };
    let r = await otp();
    userIds.push(r.body.user.id);
    if (role) {
      await prisma.user.update({ where: { id: r.body.user.id }, data: { role } });
      r = await otp(); // role is in the token
    }
    return { Authorization: `Bearer ${r.body.accessToken}` };
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
    const live = await prisma.rideCard.findMany({ where: { active: true }, select: { id: true } });
    paused = live.map((c) => c.id);
    await prisma.rideCard.updateMany({ where: { id: { in: paused } }, data: { active: false } });
    await prisma.promoCode.create({ data: { code: promoCode, value: 5 } });
  });

  // app.close() drains in-flight BullMQ jobs; see app.e2e-spec.ts.
  afterAll(async () => {
    await prisma.rideCard.deleteMany({ where: { id: { in: createdCards } } });
    await prisma.rideCard.updateMany({ where: { id: { in: paused } }, data: { active: true } });
    await prisma.promoCode.deleteMany({ where: { code: promoCode } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  it('serves only live cards, in order, at most three', async () => {
    const admin = await login('admin');
    const rider = await login();
    const make = (body: object) => {
      const req = request(server).post('/api/v1/admin/content/ride-cards').set(admin).send({
        title: 'T',
        body: 'B',
        ctaType: 'none',
        ...body,
      });
      return {
        expect: async (code: number) => {
          const res = await req.expect(code);
          if (res.body?.id) createdCards.push(res.body.id);
          return res;
        },
      };
    };
    const hour = 3600_000;
    await make({ title: 'Second', sortOrder: 2 }).expect(201);
    await make({ title: 'First', sortOrder: 1 }).expect(201);
    await make({ title: 'Third', sortOrder: 3 }).expect(201);
    await make({ title: 'Fourth', sortOrder: 4 }).expect(201);
    await make({ title: 'Paused', active: false }).expect(201);
    await make({ title: 'Later', startsAt: new Date(Date.now() + hour).toISOString() }).expect(201);
    await make({
      title: 'Over',
      startsAt: new Date(Date.now() - 2 * hour).toISOString(),
      endsAt: new Date(Date.now() - hour).toISOString(),
    }).expect(201);

    const live = await request(server).get('/api/v1/content/ride-cards').set(rider).expect(200);
    expect(live.body.map((c: { title: string }) => c.title)).toEqual(['First', 'Second', 'Third']);

    const all = await request(server).get('/api/v1/admin/content/ride-cards').set(admin).expect(200);
    expect(all.body.filter((c: { id: string }) => createdCards.includes(c.id))).toHaveLength(7);
  });

  it('refuses cards whose button would lead nowhere', async () => {
    const admin = await login('admin');
    const post = (body: object) =>
      request(server)
        .post('/api/v1/admin/content/ride-cards')
        .set(admin)
        .send({ title: 'Promo', body: 'Save on your next ride', ...body });

    const noCode = await post({ ctaType: 'promo_code', ctaLabel: 'Copy code', ctaValue: 'NOPE123' });
    expect(noCode.status).toBe(400);
    expect(noCode.body.message).toMatch(/no active promo code/);

    const http = await post({ ctaType: 'url', ctaLabel: 'Open', ctaValue: 'http://example.com' });
    expect(http.status).toBe(400);
    expect(http.body.message).toMatch(/https/);

    await post({ ctaType: 'url', ctaValue: 'https://fairsvia.com' }).expect(400);

    const ok = await post({
      ctaType: 'promo_code',
      ctaLabel: 'Copy code',
      ctaValue: promoCode.toLowerCase(),
    }).expect(201);
    createdCards.push(ok.body.id);
    expect(ok.body.ctaValue).toBe(promoCode);
  });

  it('riders can read cards but never manage them', async () => {
    const rider = await login();
    await request(server).get('/api/v1/admin/content/ride-cards').set(rider).expect(403);
    await request(server)
      .post('/api/v1/admin/content/ride-cards')
      .set(rider)
      .send({ title: 'x', body: 'y', ctaType: 'none' })
      .expect(403);
  });
});
