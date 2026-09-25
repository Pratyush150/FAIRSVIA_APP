import { formatMoney, marketCurrency, roundFare, splitPayout } from './money';

describe('money', () => {
  it('formats each launch currency the way people write it', () => {
    expect(formatMoney(245, 'INR')).toBe('₹245');
    expect(formatMoney(245.5, 'INR')).toBe('₹245.50');
    expect(formatMoney(12.3, 'USD')).toBe('$12.30');
    expect(formatMoney(18500, 'UZS')).toBe("18 500 so'm");
    expect(formatMoney(-4, 'INR')).toBe('-₹4');
    expect(formatMoney(12.3, 'EUR')).toBe('EUR 12.30');
  });

  it('reads MARKET_CURRENCY, defaulting to USD, and rejects junk', () => {
    expect(marketCurrency({})).toBe('USD');
    expect(marketCurrency({ MARKET_CURRENCY: 'inr' })).toBe('INR');
    expect(() => marketCurrency({ MARKET_CURRENCY: 'rupees' })).toThrow(/ISO 4217/);
  });

  it('rounds fares to whole rupees / som, and to cents elsewhere', () => {
    expect(roundFare(101.73, 'INR')).toBe(102);
    expect(roundFare(101.49, 'inr')).toBe(101);
    expect(roundFare(18499.6, 'UZS')).toBe(18500);
    expect(roundFare(12.345, 'USD')).toBe(12.35);
  });

  describe('splitPayout', () => {
    const sums = (r: { driverPayout: number; platformFee: number }, fare: number) =>
      expect(Math.round((r.driverPayout + r.platformFee) * 100) / 100).toBe(fare);

    it('pays the driver whole rupees and gives the platform the remainder', () => {
      expect(splitPayout(89, 89, 0.8, 'INR')).toEqual({ driverPayout: 71, platformFee: 18 });
      expect(splitPayout(75, 75, 0.8, 'INR')).toEqual({ driverPayout: 60, platformFee: 15 });
      // Cancellation / no-show fee.
      expect(splitPayout(50, 50, 0.8, 'INR')).toEqual({ driverPayout: 40, platformFee: 10 });
    });

    it('stays whole and sums exactly for odd amounts', () => {
      for (const fare of [1, 3, 7, 13, 89, 101, 142, 257, 999, 1234]) {
        const r = splitPayout(fare, fare, 0.8, 'INR');
        expect(Number.isInteger(r.driverPayout)).toBe(true);
        expect(Number.isInteger(r.platformFee)).toBe(true);
        sums(r, fare);
      }
      // Uzbek som behaves the same way.
      const uz = splitPayout(18_503, 18_503, 0.8, 'UZS');
      expect(uz).toEqual({ driverPayout: 14_802, platformFee: 3_701 });
    });

    it('keeps cents in USD', () => {
      expect(splitPayout(12.34, 12.34, 0.8, 'USD')).toEqual({ driverPayout: 9.87, platformFee: 2.47 });
      expect(splitPayout(89, 89, 0.8, 'USD')).toEqual({ driverPayout: 71.2, platformFee: 17.8 });
    });

    it('computes the driver share on the pre-promo fare (platform absorbs the promo)', () => {
      // ₹89 ride, ₹20 promo: rider pays 69, driver still gets 71, platform -2.
      expect(splitPayout(89, 69, 0.8, 'INR')).toEqual({ driverPayout: 71, platformFee: -2 });
    });
  });
});
