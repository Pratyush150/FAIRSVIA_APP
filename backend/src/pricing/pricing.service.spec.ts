import { PricingService } from './pricing.service';
import { PrismaService } from '../common/prisma/prisma.service';

describe('PricingService', () => {
  // No DB in this unit test — the service's cache defaults to the code config,
  // so the pure fare math is exercised without touching Prisma.
  const pricing = new PricingService({} as unknown as PrismaService);

  it('computes economy fare = (base + perKm*km + perMin*min)*surge + bookingFee', () => {
    // 5 km, 10 min, economy: (30 + 12*5 + 1.5*10)*1 + 10 = 115
    const est = pricing.estimateForTier('economy', 5000, 600, 1);
    expect(est.fare).toBe(115);
    expect(est.currency).toBe('INR');
    expect(est.etaSeconds).toBe(600);
  });

  it('enforces the minimum fare for very short trips', () => {
    // 100 m, 60 s economy: 30 + 1.2 + 1.5 + 10 = 42.7 -> floored to minFare 60
    const est = pricing.estimateForTier('economy', 100, 60, 1);
    expect(est.fare).toBe(60);
  });

  it('applies the surge multiplier to base/distance/time but not booking fee', () => {
    // 5 km, 10 min, surge 2: (30 + 60 + 15)*2 + 10 = 220
    const est = pricing.estimateForTier('economy', 5000, 600, 2);
    expect(est.fare).toBe(220);
    expect(est.breakdown.surgeMultiplier).toBe(2);
  });

  it('returns an estimate for every tier', () => {
    const all = pricing.estimateAllTiers(5000, 600, 1);
    expect(all.map((t) => t.tier)).toEqual([
      'economy',
      'comfort',
      'xl',
      'premium',
    ]);
    // Premium should cost more than economy for the same trip.
    expect(all[3].fare).toBeGreaterThan(all[0].fare);
  });

  it('rejects an unknown tier', () => {
    expect(() => pricing.estimateForTier('gold', 5000, 600)).toThrow();
  });
});
