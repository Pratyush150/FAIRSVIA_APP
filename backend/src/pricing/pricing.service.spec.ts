import { PricingService } from './pricing.service';
import { FARE_CONFIG } from './fare-config';
import { PrismaService } from '../common/prisma/prisma.service';

describe('PricingService', () => {
  // No DB in this unit test — the service's cache defaults to the code config,
  // so the pure fare math is exercised without touching Prisma.
  const pricing = new PricingService({} as unknown as PrismaService);

  it('computes economy fare = (base + perMile*mi + perMin*min)*surge + bookingFee', () => {
    // 5000 m ≈ 3.107 mi, 10 min, economy:
    // (2.5 + 1.2*3.107 + 0.25*10)*1 + 2.0 = 10.73
    const est = pricing.estimateForTier('economy', 5000, 600, 1);
    expect(est.fare).toBeCloseTo(10.73, 2);
    expect(est.currency).toBe('USD');
    expect(est.etaSeconds).toBe(600);
  });

  it('enforces the minimum fare for very short trips', () => {
    // 100 m, 60 s economy: 2.5 + ~0.07 + 0.25 + 2.0 ≈ 4.82 -> floored to minFare 6.5
    const est = pricing.estimateForTier('economy', 100, 60, 1);
    expect(est.fare).toBe(6.5);
  });

  it('applies the surge multiplier to base/distance/time but not booking fee', () => {
    // 5000 m ≈ 3.107 mi, 10 min, surge 2:
    // (2.5 + 1.2*3.107 + 0.25*10)*2 + 2.0 = 19.46
    const est = pricing.estimateForTier('economy', 5000, 600, 2);
    expect(est.fare).toBeCloseTo(19.46, 2);
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

  it('exposes each tier minimum fare and rejects unknown tiers', () => {
    expect(pricing.minFareFor('economy')).toBe(FARE_CONFIG.economy.minFare);
    expect(pricing.minFareFor('premium')).toBe(FARE_CONFIG.premium.minFare);
    expect(() => pricing.minFareFor('rocket')).toThrow(/Unknown tier/);
  });
});
