import { ComparisonService } from './comparison.service';
import { PricingService } from '../pricing/pricing.service';
import { CalibrationService } from './calibration.service';
import { ProviderFareModel } from './competitor-config';

// Calibration is exercised via injected `models` in these tests, so a stub that
// returns the defaults is enough for the constructor.
function fakeCalibration(models: ProviderFareModel[]): CalibrationService {
  return { models: () => models } as unknown as CalibrationService;
}

/**
 * A tiny fake PricingService that returns a fixed fare for our tier, so the
 * comparison math is tested in isolation from the DB-backed fare config.
 */
function fakePricing(ourFare: number): PricingService {
  const est = () => ({
      tier: 'economy',
      label: 'Economy',
      capacity: 4,
      fare: ourFare,
      currency: 'USD',
      etaSeconds: 600,
      breakdown: {
        baseFare: 2.5,
        distanceFare: 0,
        timeFare: 0,
        bookingFee: 2,
        surgeMultiplier: 1,
      },
    });
  return {
    estimateForTier: est,
    estimateForTierInCurrency: est,
  } as unknown as PricingService;
}

// Deterministic competitor set for assertions.
const MODELS: ProviderFareModel[] = [
  {
    provider: 'uber',
    displayName: 'Uber',
    productName: 'UberX',
    baseFare: 2.55,
    perMile: 1.15,
    perMin: 0.24,
    bookingFee: 2.9,
    minFare: 8.5,
    surgeSensitivity: 1.0,
  },
  {
    provider: 'empower',
    displayName: 'Empower',
    productName: 'Standard',
    baseFare: 1.5,
    perMile: 0.95,
    perMin: 0.18,
    bookingFee: 0,
    minFare: 6.0,
    surgeSensitivity: 0.0,
  },
];

// 5 miles @ 20 minutes → known metered numbers.
const FIVE_MILES_M = 5 * 1609.34;
const TWENTY_MIN_S = 20 * 60;

describe('ComparisonService', () => {
  it('models each competitor from its rate card', () => {
    const svc = new ComparisonService(fakePricing(14), fakeCalibration(MODELS));
    const c = svc.compare(FIVE_MILES_M, TWENTY_MIN_S, 1, 'economy', MODELS, 'USD');

    // Uber: (2.55 + 1.15*5 + 0.24*20)*1 + 2.90 = 2.55+5.75+4.80+2.90 = 16.00
    const uber = c.quotes.find((q) => q.provider === 'uber')!;
    expect(uber.price).toBeCloseTo(16.0, 2);
    expect(uber.estimated).toBe(true);

    // Empower: (1.5 + 0.95*5 + 0.18*20) + 0 = 1.5+4.75+3.60 = 9.85
    const empower = c.quotes.find((q) => q.provider === 'empower')!;
    expect(empower.price).toBeCloseTo(9.85, 2);
  });

  it('flags our own quote as real (not estimated) and identifies the cheapest', () => {
    const svc = new ComparisonService(fakePricing(9.0), fakeCalibration(MODELS));
    const c = svc.compare(FIVE_MILES_M, TWENTY_MIN_S, 1, 'economy', MODELS, 'USD');

    const ours = c.quotes.find((q) => q.isOurs)!;
    expect(ours.provider).toBe('ubernav');
    expect(ours.estimated).toBe(false);

    // Prices: ubernav 9.00, empower 9.85, uber 16.00 → we're cheapest.
    expect(c.cheapest.provider).toBe('ubernav');
    expect(c.ours.isCheapest).toBe(true);
    expect(c.ours.rank).toBe(1);
  });

  it('returns the minimum across providers when a competitor undercuts us', () => {
    const svc = new ComparisonService(fakePricing(12.0), fakeCalibration(MODELS));
    const c = svc.compare(FIVE_MILES_M, TWENTY_MIN_S, 1, 'economy', MODELS, 'USD');

    // empower 9.85 < ubernav 12.00 < uber 16.00
    expect(c.cheapest.provider).toBe('empower');
    expect(c.cheapest.price).toBeCloseTo(9.85, 2);
    expect(c.ours.isCheapest).toBe(false);
    expect(c.ours.rank).toBe(2);
  });

  it('sorts quotes ascending and computes per-competitor deltas', () => {
    const svc = new ComparisonService(fakePricing(12.0), fakeCalibration(MODELS));
    const c = svc.compare(FIVE_MILES_M, TWENTY_MIN_S, 1, 'economy', MODELS, 'USD');

    const prices = c.quotes.map((q) => q.price);
    expect(prices).toEqual([...prices].sort((a, b) => a - b));

    // vs Uber (16.00): we're cheaper by 4.00 → negative diff.
    const vsUber = c.ours.vs.find((v) => v.provider === 'uber')!;
    expect(vsUber.diff).toBeCloseTo(-4.0, 2);
    expect(vsUber.pct).toBeLessThan(0);

    // maxSavings = priciest (uber 16) - ours (12) = 4.00
    expect(c.ours.maxSavings).toBeCloseTo(4.0, 2);
  });

  it('amplifies competitor prices under surge per sensitivity', () => {
    const svc = new ComparisonService(fakePricing(12.0), fakeCalibration(MODELS));
    const flat = svc.compare(FIVE_MILES_M, TWENTY_MIN_S, 1, 'economy', MODELS, 'USD');
    const surged = svc.compare(FIVE_MILES_M, TWENTY_MIN_S, 2, 'economy', MODELS, 'USD');

    const uberFlat = flat.quotes.find((q) => q.provider === 'uber')!.price;
    const uberSurged = surged.quotes.find((q) => q.provider === 'uber')!.price;
    // Uber sensitivity 1.0 → metered doubles at surge 2.
    expect(uberSurged).toBeGreaterThan(uberFlat);

    // Empower sensitivity 0 → price unchanged by surge.
    const empFlat = flat.quotes.find((q) => q.provider === 'empower')!.price;
    const empSurged = surged.quotes.find((q) => q.provider === 'empower')!.price;
    expect(empSurged).toBeCloseTo(empFlat, 2);
  });

  it('always carries the estimate disclaimer', () => {
    const svc = new ComparisonService(fakePricing(9), fakeCalibration(MODELS));
    const c = svc.compare(FIVE_MILES_M, TWENTY_MIN_S, 1, 'economy', undefined, 'USD');
    expect(c.disclaimer).toMatch(/estimate/i);
  });

  it('gives competitors a confidence band but our own quote is exact', () => {
    const svc = new ComparisonService(fakePricing(12), fakeCalibration(MODELS));
    const c = svc.compare(FIVE_MILES_M, TWENTY_MIN_S, 1, 'economy', MODELS, 'USD');

    const ours = c.quotes.find((q) => q.isOurs)!;
    expect(ours.confidence).toBe('exact');
    expect(ours.priceLow).toBe(ours.price);
    expect(ours.priceHigh).toBe(ours.price);

    const uber = c.quotes.find((q) => q.provider === 'uber')!;
    expect(uber.priceLow).toBeLessThan(uber.price);
    expect(uber.priceHigh).toBeGreaterThan(uber.price);
  });

  it('widens the competitor band and flags high demand under surge', () => {
    const svc = new ComparisonService(fakePricing(12), fakeCalibration(MODELS));
    const flat = svc.compare(FIVE_MILES_M, TWENTY_MIN_S, 1, 'economy', MODELS, 'USD');
    const surged = svc.compare(FIVE_MILES_M, TWENTY_MIN_S, 2, 'economy', MODELS, 'USD');

    const bandFlat = (q: string, c = flat) => {
      const x = c.quotes.find((v) => v.provider === q)!;
      return x.priceHigh - x.priceLow;
    };
    // Uber surges → wider band at surge 2 than at surge 1.
    expect(bandFlat('uber', surged)).toBeGreaterThan(bandFlat('uber'));
    // Empower has zero surge sensitivity → band unchanged by surge.
    expect(bandFlat('empower', surged)).toBeCloseTo(bandFlat('empower'), 2);

    expect(flat.demandHigh).toBe(false);
    expect(surged.demandHigh).toBe(true);
  });
});

describe('ComparisonService — per-tier comparisons (INR)', () => {
  // Our fare per tier (the pilot's INR per-km ratios), competitor sets real.
  const OUR: Record<string, number> = { economy: 60, comfort: 75, xl: 100, premium: 140 };
  const pricing = {
    estimateForTierInCurrency: (tier: string) => ({ tier, label: tier, fare: OUR[tier] }),
  } as unknown as PricingService;
  const svc = new ComparisonService(pricing, fakeCalibration([]));
  const DAY = new Date('2026-09-26T04:30:00Z');

  it('compares each tier against that tier’s products, with distinct numbers', () => {
    const byTier = Object.fromEntries(
      ['economy', 'comfort', 'xl', 'premium'].map((t) => [
        t,
        svc.compare(5000, 900, 1, t, undefined, 'INR', DAY),
      ]),
    );
    expect(byTier.economy.quotes.map((q) => q.productName)).toEqual(
      expect.arrayContaining(['Uber Go', 'Mini', 'Cab Economy']),
    );
    expect(byTier.xl.quotes.map((q) => q.productName)).toEqual(
      expect.arrayContaining(['Uber XL', 'Prime SUV', 'Cab XL']),
    );
    const uber = (t: string) => byTier[t].quotes.find((q) => q.provider === 'uber')!.price;
    expect([uber('economy'), uber('comfort'), uber('xl'), uber('premium')]).toEqual([131, 180, 263, 328]);
    for (const t of Object.keys(OUR)) {
      expect(byTier[t].tier).toBe(t);
      expect(byTier[t].ours.price).toBe(OUR[t]);
    }
    expect(byTier.premium.quotes).toHaveLength(2); // us + Uber Black only
  });

  it('a tier without a competitor set in that market compares against nothing', () => {
    const c = svc.compare(5000, 900, 1, 'xl', undefined, 'AED', DAY);
    expect(c.quotes).toHaveLength(1);
  });
});
