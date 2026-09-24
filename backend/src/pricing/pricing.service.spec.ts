import { PricingService } from './pricing.service';
import { FARE_CONFIG, INR_FARE_CONFIG, defaultFareConfig } from './fare-config';
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
    // The base line carries the surge too — it is part of what is multiplied.
    expect(est.breakdown.baseFare).toBeCloseTo(5, 2);
    expect(est.breakdown.bookingFee).toBe(2);
  });

  /**
   * The rider's "Details" list is these lines. If they don't add up to the
   * price on the button, the app is showing them arithmetic that is wrong.
   */
  describe('the breakdown always sums to the quoted fare', () => {
    const sum = (b: {
      baseFare: number;
      distanceFare: number;
      timeFare: number;
      bookingFee: number;
      minimumFareAdjustment: number;
    }) =>
      Math.round(
        (b.baseFare + b.distanceFare + b.timeFare + b.bookingFee +
          b.minimumFareAdjustment) * 100,
      ) / 100;

    it.each([
      ['a normal trip', 5000, 600, 1],
      ['a surged trip', 5000, 600, 2],
      ['an odd surge', 8321, 977, 1.7],
      ['a minimum-fare trip', 100, 60, 1],
      ['a surged minimum-fare trip', 100, 60, 1.3],
      ['a zero-distance trip', 0, 0, 1],
    ])('%s', (_label, distanceM, durationS, surge) => {
      for (const tier of ['bike', 'auto', 'economy', 'comfort', 'xl', 'premium']) {
        const est = pricing.estimateForTier(tier, distanceM, durationS, surge);
        expect(sum(est.breakdown)).toBe(est.fare);
      }
    });

    it('reports the shortfall as a minimum-fare line only when it applies', () => {
      // Long trip: nothing to top up.
      expect(
        pricing.estimateForTier('economy', 20000, 1800, 1).breakdown
          .minimumFareAdjustment,
      ).toBe(0);
      // 100 m / 60 s economy is floored from ~4.82 to 6.50.
      const short = pricing.estimateForTier('economy', 100, 60, 1);
      expect(short.fare).toBe(6.5);
      expect(short.breakdown.minimumFareAdjustment).toBeGreaterThan(0);
    });
  });

  it('returns an estimate for every tier', () => {
    const all = pricing.estimateAllTiers(5000, 600, 1);
    // Cheapest first: bike and auto lead, then the cars.
    expect(all.map((t) => t.tier)).toEqual([
      'bike',
      'auto',
      'economy',
      'comfort',
      'xl',
      'premium',
    ]);
    const fare = (t: string) => all.find((e) => e.tier === t)!.fare;
    expect(fare('bike')).toBeLessThan(fare('auto'));
    expect(fare('auto')).toBeLessThan(fare('economy'));
    // Premium should cost more than economy for the same trip.
    expect(fare('premium')).toBeGreaterThan(fare('economy'));
    // Seats: a bike carries one, an auto three.
    expect(all.find((e) => e.tier === 'bike')!.capacity).toBe(1);
    expect(all.find((e) => e.tier === 'auto')!.capacity).toBe(3);
  });

  it('rejects an unknown tier', () => {
    expect(() => pricing.estimateForTier('gold', 5000, 600)).toThrow();
  });

  it('exposes each tier minimum fare and rejects unknown tiers', () => {
    expect(pricing.minFareFor('economy')).toBe(FARE_CONFIG.economy.minFare);
    expect(pricing.minFareFor('premium')).toBe(FARE_CONFIG.premium.minFare);
    expect(() => pricing.minFareFor('rocket')).toThrow(/Unknown tier/);
  });

  it('quotes whole rupees in an INR market, and the lines still add up', () => {
    jest.isolateModules(() => {
      const prev = process.env.MARKET_CURRENCY;
      process.env.MARKET_CURRENCY = 'INR';
      try {
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        const { PricingService: InrPricing } = require('./pricing.service');
        const inr = new InrPricing({} as unknown as PrismaService);
        for (const [m, s, surge] of [
          [3217, 611, 1],
          [12877, 1733, 1.3],
          [800, 190, 1.7],
        ] as const) {
          for (const e of inr.estimateAllTiers(m, s, surge)) {
            expect(e.currency).toBe('INR');
            expect(Number.isInteger(e.fare)).toBe(true);
            const b = e.breakdown;
            expect(
              b.baseFare + b.distanceFare + b.timeFare + b.bookingFee +
                b.minimumFareAdjustment,
            ).toBeCloseTo(e.fare, 6);
          }
        }
      } finally {
        if (prev === undefined) delete process.env.MARKET_CURRENCY;
        else process.env.MARKET_CURRENCY = prev;
      }
    });
  });

  /** Pune pilot: auto and bike quote the government meter, to the rupee. */
  describe('Pune auto and bike tariffs (INR defaults)', () => {
    const withInr = (fn: (inr: PricingService) => void) =>
      jest.isolateModules(() => {
        const prev = process.env.MARKET_CURRENCY;
        process.env.MARKET_CURRENCY = 'INR';
        try {
          // eslint-disable-next-line @typescript-eslint/no-require-imports
          const { PricingService: InrPricing } = require('./pricing.service');
          fn(new InrPricing({} as unknown as PrismaService));
        } finally {
          if (prev === undefined) delete process.env.MARKET_CURRENCY;
          else process.env.MARKET_CURRENCY = prev;
        }
      });

    it('auto: ₹30 for the first 1.5 km, then ₹20/km (Pune RTA, Sep 2026)', () => {
      withInr((inr) => {
        // Anything up to 1.5 km is the ₹30 minimum.
        expect(inr.estimateForTier('auto', 800, 180).fare).toBe(30);
        expect(inr.estimateForTier('auto', 1500, 300).fare).toBe(30);
        // 5 km on the meter: 5 × ₹20 = ₹100. Time is not charged.
        const five = inr.estimateForTier('auto', 5000, 900);
        expect(five.fare).toBe(100);
        expect(five.currency).toBe('INR');
        expect(five.breakdown.baseFare).toBe(0);
        expect(five.breakdown.timeFare).toBe(0);
        expect(five.breakdown.bookingFee).toBe(0);
        expect(five.capacity).toBe(3);
      });
    });

    it('bike: ₹15 for the first 1.5 km, then ₹10.27/km (Maharashtra Bike Taxi Rules 2025)', () => {
      withInr((inr) => {
        expect(inr.estimateForTier('bike', 1000, 240).fare).toBe(15);
        // 5 km: 5 × 10.27 = 51.35 → ₹51.
        expect(inr.estimateForTier('bike', 5000, 900).fare).toBe(51);
        expect(inr.estimateForTier('bike', 5000, 900).capacity).toBe(1);
      });
    });

    it('lists bike and auto before the cars in INR too', () => {
      withInr((inr) => {
        expect(inr.listConfig().map((c) => c.tier)).toEqual([
          'bike', 'auto', 'economy', 'comfort', 'xl', 'premium',
        ]);
      });
    });
  });

  describe('defaults per market', () => {
    it('uses the rupee table in INR and the dollar table otherwise', () => {
      expect(defaultFareConfig('INR')).toBe(INR_FARE_CONFIG);
      expect(defaultFareConfig('inr')).toBe(INR_FARE_CONFIG);
      expect(defaultFareConfig('USD')).toBe(FARE_CONFIG);
    });

    it('both tables cover the same tiers', () => {
      expect(Object.keys(INR_FARE_CONFIG).sort()).toEqual(
        Object.keys(FARE_CONFIG).sort(),
      );
    });

    it('seeds only the tiers the table is missing, never touching tuned rows', async () => {
      const createMany = jest.fn().mockResolvedValue({ count: 2 });
      const prisma = {
        fareConfig: {
          // An existing deployment: the four car tiers, admin-tuned.
          findMany: jest
            .fn()
            .mockResolvedValueOnce(
              ['economy', 'comfort', 'xl', 'premium'].map((tier) => ({ tier })),
            )
            .mockResolvedValue([]),
          createMany,
        },
      } as unknown as PrismaService;
      await new PricingService(prisma).onModuleInit();
      expect(createMany).toHaveBeenCalledTimes(1);
      const rows = createMany.mock.calls[0][0].data as { tier: string }[];
      expect(rows.map((r) => r.tier)).toEqual(['bike', 'auto']);
      expect(createMany.mock.calls[0][0].skipDuplicates).toBe(true);
    });

    it('seeds nothing when every tier already has a row', async () => {
      const createMany = jest.fn();
      const prisma = {
        fareConfig: {
          findMany: jest
            .fn()
            .mockResolvedValue(Object.keys(FARE_CONFIG).map((tier) => ({ tier }))),
          createMany,
        },
      } as unknown as PrismaService;
      await new PricingService(prisma).onModuleInit();
      expect(createMany).not.toHaveBeenCalled();
    });
  });
});
