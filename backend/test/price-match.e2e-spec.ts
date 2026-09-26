import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';

/**
 * Price match (PRICE_MATCH_ENABLED, default on): every tier with a competitor
 * set is quoted at min(our fare, cheapest competitor - max(1, 3%)), never below
 * PRICE_MATCH_FLOOR; the tier list, the comparison card and the breakdown agree.
 */
describe('Price match (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  let userId: string;
  let auth: { Authorization: string };

  beforeAll(async () => {
    delete process.env.PRICE_MATCH_ENABLED;
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api/v1', { exclude: [{ path: 'metrics', method: RequestMethod.GET }] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
    await app.init();
    server = app.getHttpServer();
    prisma = app.get(PrismaService);
    redis = app.get(RedisService);
    const phone = `+1996${Math.floor(1e6 + Math.random() * 8e6)}`;
    await redis.client.del(`otp:rate:${phone}`);
    const r1 = await request(server).post('/api/v1/auth/otp/request').send({ phone });
    const r2 = await request(server).post('/api/v1/auth/otp/verify').send({ phone, code: r1.body.devCode });
    userId = r2.body.user.id;
    auth = { Authorization: `Bearer ${r2.body.accessToken}` };
  });

  afterAll(async () => {
    await prisma.user.deleteMany({ where: { id: userId } });
    await app.close();
  }, 60_000);

  it('quotes each compared tier at the matched fare, consistently across list, card and breakdown', async () => {
    const res = await request(server).post('/api/v1/trips/estimate').set(auth)
      .send({ pickupLat: 28.5383, pickupLng: -81.3792, dropoffLat: 28.55, dropoffLng: -81.36 })
      .expect(200);
    const byTier = res.body.comparisonsByTier as Record<string, {
      quotes: { isOurs: boolean; price: number }[];
      ours: { priceMatch: { fare: number; computedFare: number; applied: boolean; floorBlocked: boolean } };
    }>;
    const tiers = Object.keys(byTier);
    expect(tiers.length).toBeGreaterThan(0);
    const floor = Number(process.env.PRICE_MATCH_FLOOR ?? 30);
    for (const t of tiers) {
      const cmp = byTier[t];
      const pm = cmp.ours.priceMatch;
      const listed = (res.body.tiers as { tier: string; fare: number; breakdown: { priceMatchDiscount?: number } }[])
        .find((x) => x.tier === t)!;
      const ours = cmp.quotes.find((q) => q.isOurs)!;
      const cheapestRival = Math.min(...cmp.quotes.filter((q) => !q.isOurs).map((q) => q.price));
      // The list, the card and the match agree on one number.
      expect(listed.fare).toBe(pm.fare);
      expect(ours.price).toBe(pm.fare);
      expect(pm.fare).toBeLessThanOrEqual(pm.computedFare);
      if (pm.applied) {
        // Breakdown carries the discount so it still sums to the fare.
        expect(listed.breakdown.priceMatchDiscount).toBeCloseTo(pm.computedFare - pm.fare, 2);
        if (!pm.floorBlocked) {
          expect(pm.fare).toBeLessThanOrEqual(cheapestRival - Math.max(1, cheapestRival * 0.03) + 1e-9);
        } else {
          expect(pm.fare).toBeGreaterThanOrEqual(Math.min(pm.computedFare, floor));
        }
      } else {
        expect(listed.breakdown.priceMatchDiscount ?? 0).toBe(0);
      }
    }
  });
});
