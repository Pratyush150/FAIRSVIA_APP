import { ComparisonService } from './comparison.service';
import { PricingService } from '../pricing/pricing.service';
import { CalibrationService } from './calibration.service';
import { INR_FARE_CONFIG } from '../pricing/fare-config';
import { applyPriceMatch, priceMatchConfig } from './price-match';
import { withPriceMatch } from '../trips/trips.service';

/**
 * Owner rule: RideVela is the cheapest in every scenario. Our fare comes down
 * (price match); the competitor models are untouched.
 */
function svc(): ComparisonService {
  // Real pricing math on the INR seed card (no DB).
  const pricing = Object.create(PricingService.prototype) as PricingService;
  (pricing as unknown as { cache: unknown }).cache = INR_FARE_CONFIG;
  const calibration = { models: () => [] } as unknown as CalibrationService;
  return new ComparisonService(pricing, calibration);
}

const DAY = new Date('2026-09-26T04:30:00Z'); // 10:00 IST
const NIGHT = new Date('2026-09-25T20:00:00Z'); // 01:30 IST (night window)
const TIERS = ['economy', 'comfort', 'xl', 'premium'];
const SCENARIOS: { name: string; m: number; s: number; surge: number; at: Date }[] = [
  { name: '1 km (min fare), day', m: 1000, s: 240, surge: 1, at: DAY },
  { name: '1 km (min fare), night', m: 1000, s: 240, surge: 1, at: NIGHT },
  { name: '5 km day', m: 5000, s: 900, surge: 1, at: DAY },
  { name: '12 km night', m: 12000, s: 1800, surge: 1, at: NIGHT },
  { name: '5 km surge 1.5', m: 5000, s: 900, surge: 1.5, at: DAY },
  { name: '5 km surge 2.0 (max)', m: 5000, s: 900, surge: 2, at: DAY },
  { name: '12 km surge 2.0 night', m: 12000, s: 1800, surge: 2, at: NIGHT },
  { name: '30 km day', m: 30000, s: 3600, surge: 1, at: DAY },
];

describe('price match — RideVela always cheapest (INR, every tier)', () => {
  const env = { ...process.env };
  afterEach(() => {
    process.env = { ...env };
  });

  const rows: string[] = [];
  afterAll(() => {
    // Evidence table in the test log.
    // eslint-disable-next-line no-console
    console.log(['scenario | tier | ours(computed→quoted) | cheapest competitor', ...rows].join('\n'));
  });

  for (const sc of SCENARIOS) {
    for (const tier of TIERS) {
      it(`${sc.name} — ${tier}: ourIsCheapest, strictly below every competitor`, () => {
        delete process.env.PRICE_MATCH_ENABLED;
        const c = svc().compare(sc.m, sc.s, sc.surge, tier, undefined, 'INR', sc.at);
        const others = c.quotes.filter((q) => !q.isOurs);
        const cheapestOther = Math.min(...others.map((q) => q.price));
        rows.push(
          `${sc.name} | ${tier} | ${c.ours.priceMatch.computedFare}→${c.ours.price} | ${cheapestOther}`,
        );
        expect(c.ours.isCheapest).toBe(true);
        expect(c.ours.rank).toBe(1);
        expect(c.ours.price).toBeLessThan(cheapestOther);
        expect(Number.isInteger(c.ours.price)).toBe(true);
        expect(c.ours.price).toBeGreaterThanOrEqual(30);
        expect(c.ours.priceMatch.floorBlocked).toBe(false);
        // Never priced UP by the match.
        expect(c.ours.price).toBeLessThanOrEqual(c.ours.priceMatch.computedFare);
      });
    }
  }

  it('1 km economy: the ₹75 minimum is matched under Rapido (the reported case)', () => {
    const c = svc().compare(1000, 240, 1, 'economy', undefined, 'INR', DAY);
    expect(c.ours.priceMatch.computedFare).toBe(75);
    expect(c.ours.priceMatch.applied).toBe(true);
    expect(c.ours.price).toBeLessThan(c.quotes.find((q) => q.provider === 'rapido')!.price);
  });

  it('competitor quotes are identical with the match on or off', () => {
    const on = svc().compare(1000, 240, 2, 'economy', undefined, 'INR', DAY);
    process.env.PRICE_MATCH_ENABLED = 'false';
    const off = svc().compare(1000, 240, 2, 'economy', undefined, 'INR', DAY);
    const strip = (q: typeof on.quotes) => q.filter((x) => !x.isOurs);
    expect(strip(on.quotes)).toEqual(strip(off.quotes));
  });

  it('PRICE_MATCH_ENABLED=false restores the old behaviour (our computed fare)', () => {
    process.env.PRICE_MATCH_ENABLED = 'false';
    const c = svc().compare(1000, 240, 1, 'economy', undefined, 'INR', DAY);
    expect(c.ours.price).toBe(75);
    expect(c.ours.priceMatch.applied).toBe(false);
    expect(c.ours.isCheapest).toBe(false); // Rapido's modelled minimum is lower
  });

  it('undercut = max(₹1, pct) and rounds down to whole rupees', () => {
    const cfg = { enabled: true, undercutPct: 3, floor: 30 };
    expect(applyPriceMatch(200, [100], 'INR', cfg).fare).toBe(97);
    expect(applyPriceMatch(200, [20.5], 'INR', { ...cfg, floor: 0 }).fare).toBe(19);
    expect(applyPriceMatch(90, [100], 'INR', cfg).applied).toBe(false); // already cheaper
    process.env.PRICE_MATCH_UNDERCUT_PCT = '10';
    expect(applyPriceMatch(200, [100], 'INR', priceMatchConfig()).fare).toBe(90);
  });

  it('the floor wins over "cheapest" (and is reported), never below it', () => {
    const cfg = { enabled: true, undercutPct: 3, floor: 30 };
    const r = applyPriceMatch(75, [25], 'INR', cfg);
    expect(r.fare).toBe(30);
    expect(r.floorBlocked).toBe(true);
    // Floor never raises a fare that was already below it.
    expect(applyPriceMatch(20, [10], 'INR', cfg).fare).toBe(20);
    process.env.PRICE_MATCH_FLOOR = '60';
    expect(applyPriceMatch(75, [62], 'INR', priceMatchConfig()).fare).toBe(60);
  });

  it('tier list fare = comparison fare, with a breakdown line that sums', () => {
    const c = svc().compare(1000, 240, 1, 'economy', undefined, 'INR', DAY);
    const est = {
      tier: 'economy', label: 'Economy', capacity: 4, fare: 75, currency: 'INR', etaSeconds: 240,
      breakdown: { baseFare: 30, distanceFare: 12, timeFare: 4, bookingFee: 0, surgeMultiplier: 1, minimumFareAdjustment: 29 },
    };
    const m = withPriceMatch(est, c);
    expect(m.fare).toBe(c.ours.price);
    const b = m.breakdown;
    expect(b.baseFare + b.distanceFare + b.timeFare + b.bookingFee + b.minimumFareAdjustment - (b.priceMatchDiscount ?? 0)).toBe(m.fare);
  });
});

describe('price match — other markets via the currency override (no INR floor)', () => {
  it('AED and UZS: RideVela cheapest too', () => {
    for (const cur of ['AED', 'UZS']) {
      const c = svc().compare(9400, 810, 1, 'economy', undefined, cur, DAY);
      expect(c.ours.isCheapest).toBe(true);
    }
  });
});
