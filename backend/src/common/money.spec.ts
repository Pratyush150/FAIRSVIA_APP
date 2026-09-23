import { formatMoney, marketCurrency } from './money';

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
});
