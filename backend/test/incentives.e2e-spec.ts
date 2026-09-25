import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';
import { QuestsService } from '../src/incentives/quests.service';

/**
 * Driver incentives (docs/plans/driver-app-benchmark.md): acceptance and
 * cancellation rates (GET /drivers/me/stats) and quests with a one-time
 * bonus (admin /admin/quests, driver GET /drivers/me/quests).
 */
describe('Driver incentives (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  const userIds: string[] = [];
  const questIds: string[] = [];

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
      r = await otp();
    }
    return { id: r.body.user.id as string, auth: { Authorization: `Bearer ${r.body.accessToken}` } };
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
    await prisma.quest.deleteMany({ where: { id: { in: questIds } } });
    await prisma.ledgerEntry.deleteMany({ where: { driverId: { in: userIds } } });
    await prisma.driverOfferEvent.deleteMany({ where: { driverId: { in: userIds } } });
    await prisma.trip.deleteMany({ where: { riderId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  describe('acceptance & cancellation rates', () => {
    it('computes both over the last 7 days, never counting a no-show cancel', async () => {
      const d = await driver();
      const trip = '00000000-0000-4000-8000-000000000000';
      const rows = [
        ...Array(7).fill('accepted'),
        ...Array(2).fill('declined'),
        'expired',
        'cancelled',
        'cancelled_no_show',
        'cancelled_no_show',
      ].map((outcome) => ({ driverId: d.id, tripId: trip, outcome }));
      await prisma.driverOfferEvent.createMany({ data: rows });
      // Outside the window: ignored.
      await prisma.driverOfferEvent.create({
        data: {
          driverId: d.id,
          tripId: trip,
          outcome: 'declined',
          createdAt: new Date(Date.now() - 8 * 86400_000),
        },
      });
      const res = await request(server).get('/api/v1/drivers/me/stats').set(d.auth).expect(200);
      expect(res.body).toMatchObject({
        window: '7d',
        offers: 10,
        accepted: 7,
        declined: 2,
        expired: 1,
        cancelled: 1,
        acceptanceRate: 0.7,
        cancellationRate: 0.143,
      });
    });

    it('a new driver has no rates yet (null, not 0%)', async () => {
      const d = await driver();
      const res = await request(server).get('/api/v1/drivers/me/stats').set(d.auth).expect(200);
      expect(res.body).toMatchObject({ offers: 0, acceptanceRate: null, cancellationRate: null });
    });

    it('a real driver cancel is recorded; a real no-show cancel is recorded apart', async () => {
      const rider = await login();
      const d = await driver();
      const mk = (status: 'accepted' | 'arrived') =>
        prisma.trip.create({
          data: {
            riderId: rider.id,
            driverId: d.id,
            status,
            pickupLat: 18.52,
            pickupLng: 73.86,
            dropoffLat: 18.55,
            dropoffLng: 73.9,
            fareEstimate: 200,
            paymentMode: 'cash',
            acceptedAt: new Date(Date.now() - 900_000),
            arrivedAt: status === 'arrived' ? new Date(Date.now() - 600_000) : null,
          },
        });
      const a = await mk('accepted');
      await request(server)
        .post(`/api/v1/trips/${a.id}/driver-cancel`)
        .set(d.auth)
        .send({ reason: 'Car trouble' })
        .expect(200);
      const b = await mk('arrived');
      await request(server)
        .post(`/api/v1/trips/${b.id}/driver-cancel`)
        .set(d.auth)
        .send({ reason: "Rider didn't show up", noShow: true })
        .expect(200);
      // Recording is fire-and-forget; give it a moment.
      await new Promise((r) => setTimeout(r, 200));
      const ev = await prisma.driverOfferEvent.findMany({ where: { driverId: d.id } });
      expect(ev.map((e) => `${e.tripId}:${e.outcome}`).sort()).toEqual(
        [`${a.id}:cancelled`, `${b.id}:cancelled_no_show`].sort(),
      );
    });
  });

  describe('quests', () => {
    const hour = 3600_000;

    const createQuest = async (
      admin: { auth: Record<string, string> },
      body: Record<string, unknown>,
    ) => {
      const res = await request(server).post('/api/v1/admin/quests').set(admin.auth).send(body);
      if (res.body?.id) questIds.push(res.body.id);
      return res;
    };

    const completed = (riderId: string, driverId: string, completedAt: Date, tier = 'economy') =>
      prisma.trip.create({
        data: {
          riderId,
          driverId,
          status: 'completed',
          tier: tier as never,
          pickupLat: 18.52,
          pickupLng: 73.86,
          dropoffLat: 18.55,
          dropoffLng: 73.9,
          fareFinal: 100,
          completedAt,
        },
      });

    it('only admins create quests; the window must be valid', async () => {
      const d = await driver();
      const admin = await login('admin');
      const now = Date.now();
      const body = {
        title: 'Test quest',
        targetTrips: 2,
        startsAt: new Date(now - hour).toISOString(),
        endsAt: new Date(now + hour).toISOString(),
        bonusAmount: 150,
      };
      await request(server).post('/api/v1/admin/quests').set(d.auth).send(body).expect(403);
      const bad = await createQuest(admin, { ...body, endsAt: new Date(now - 2 * hour).toISOString() });
      expect(bad.status).toBe(400);
    });

    it('counts trips in [startsAt, endsAt), awards the bonus once, and it shows in earnings', async () => {
      const admin = await login('admin');
      const rider = await login();
      const d = await driver();
      const startsAt = new Date(Date.now() - hour);
      const endsAt = new Date(Date.now() + hour);
      const q = await createQuest(admin, {
        title: 'Complete 2 trips — e2e',
        targetTrips: 2,
        startsAt: startsAt.toISOString(),
        endsAt: endsAt.toISOString(),
        bonusAmount: 150,
      });
      expect(q.status).toBe(201);

      // Boundaries: 1 ms before the start and exactly at the end don't count.
      await completed(rider.id, d.id, new Date(startsAt.getTime() - 1));
      await completed(rider.id, d.id, endsAt);
      await completed(rider.id, d.id, startsAt); // exactly at the start: counts

      const mine = async () => {
        const res = await request(server).get('/api/v1/drivers/me/quests').set(d.auth).expect(200);
        return (res.body as Array<Record<string, unknown>>).find((x) => x.id === q.body.id)!;
      };
      expect(await mine()).toMatchObject({
        progress: 1,
        target: 2,
        bonus: 150,
        completed: false,
        paid: false,
        status: 'active',
      });

      const t2 = await completed(rider.id, d.id, new Date());
      // Completion hook + concurrent reads race to pay: exactly one award.
      const quests = app.get(QuestsService);
      await Promise.all([
        quests.onTripCompleted(d.id, t2.id),
        quests.onTripCompleted(d.id, t2.id),
        mine(),
        mine(),
      ]);
      expect(await mine()).toMatchObject({ progress: 2, completed: true, paid: true });

      const bonus = await prisma.ledgerEntry.findMany({ where: { driverId: d.id, type: 'bonus' } });
      expect(bonus).toHaveLength(1);
      expect(Number(bonus[0].amount)).toBe(150);
      const awards = await prisma.questAward.count({ where: { questId: q.body.id, driverId: d.id } });
      expect(awards).toBe(1);

      // A third trip neither re-pays nor pushes progress past the target.
      const t3 = await completed(rider.id, d.id, new Date());
      await quests.onTripCompleted(d.id, t3.id);
      expect(await mine()).toMatchObject({ progress: 2, paid: true });
      expect(await prisma.ledgerEntry.count({ where: { driverId: d.id, type: 'bonus' } })).toBe(1);

      const earn = await request(server)
        .get('/api/v1/drivers/me/earnings?range=today')
        .set(d.auth)
        .expect(200);
      expect(earn.body.bonuses).toBe(150);
    });

    it('a tier-limited quest ignores trips in other tiers; inactive quests are hidden', async () => {
      const admin = await login('admin');
      const rider = await login();
      const d = await driver();
      const window = {
        startsAt: new Date(Date.now() - hour).toISOString(),
        endsAt: new Date(Date.now() + hour).toISOString(),
      };
      const xl = await createQuest(admin, {
        title: 'XL only — e2e',
        tiers: ['xl'],
        targetTrips: 1,
        bonusAmount: 50,
        ...window,
      });
      const off = await createQuest(admin, {
        title: 'Inactive — e2e',
        targetTrips: 1,
        bonusAmount: 50,
        active: false,
        ...window,
      });
      await completed(rider.id, d.id, new Date(), 'economy');
      const res = await request(server).get('/api/v1/drivers/me/quests').set(d.auth).expect(200);
      const ids = (res.body as Array<{ id: string }>).map((x) => x.id);
      expect(ids).not.toContain(off.body.id);
      expect(res.body.find((x: { id: string }) => x.id === xl.body.id)).toMatchObject({
        progress: 0,
        completed: false,
        paid: false,
      });
      expect(await prisma.ledgerEntry.count({ where: { driverId: d.id, type: 'bonus' } })).toBe(0);

      // Admin can list and deactivate.
      const list = await request(server).get('/api/v1/admin/quests').set(admin.auth).expect(200);
      expect(list.body.some((x: { id: string }) => x.id === xl.body.id)).toBe(true);
      await request(server)
        .patch(`/api/v1/admin/quests/${xl.body.id}`)
        .set(admin.auth)
        .send({ active: false })
        .expect(200);
    });
  });
});
