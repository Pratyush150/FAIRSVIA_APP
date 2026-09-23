/**
 * The market's currency and how money reads to a person. One place, so a
 * receipt, an error message and the app never disagree about "₹" vs "$".
 *
 * MARKET_CURRENCY (ISO 4217) picks the currency for new trips, payments,
 * payouts and ledger views. Existing rows keep the currency they were
 * written in — a trip priced in dollars stays in dollars.
 */
const KNOWN: Record<string, { symbol: string; prefix: boolean; decimals: number }> = {
  USD: { symbol: '$', prefix: true, decimals: 2 },
  INR: { symbol: '₹', prefix: true, decimals: 2 },
  // Uzbek som: no coins in circulation, prices are whole som, written after.
  UZS: { symbol: "so'm", prefix: false, decimals: 0 },
};

export function marketCurrency(env: NodeJS.ProcessEnv = process.env): string {
  const code = (env.MARKET_CURRENCY ?? 'USD').trim().toUpperCase();
  if (!/^[A-Z]{3}$/.test(code)) {
    throw new Error(`MARKET_CURRENCY "${code}" is not a 3-letter ISO 4217 code`);
  }
  return code;
}

/** "₹245", "₹245.50", "$12.30", "18 500 so'm"; unknown codes as "EUR 12.30". */
export function formatMoney(amount: number, currency: string): string {
  const spec = KNOWN[currency.toUpperCase()];
  const decimals = spec?.decimals ?? 2;
  const abs = Math.abs(amount);
  const whole = Math.abs(abs - Math.round(abs)) < 0.005;
  let n = abs.toFixed(whole || decimals === 0 ? 0 : decimals);
  if (decimals === 0) n = n.replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  const sign = amount < 0 ? '-' : '';
  if (!spec) return `${sign}${currency.toUpperCase()} ${n}`;
  return spec.prefix ? `${sign}${spec.symbol}${n}` : `${sign}${n} ${spec.symbol}`;
}
