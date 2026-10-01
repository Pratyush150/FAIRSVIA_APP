import { marketCurrency } from '../common/money';

/** The market's currency (MARKET_CURRENCY), for every new trip and estimate. */
export const CURRENCY = marketCurrency();

/** Meters in one statute mile. US fares are priced per mile, but the geo layer
 *  reports distances in meters, so this is the single conversion constant used
 *  by the pricing math (and the spec) to go meters → miles. */
export const METERS_PER_MILE = 1609.34;

export interface TierFareConfig {
  tier: string;
  label: string;
  baseFare: number;
  perMile: number;
  perMin: number;
  bookingFee: number;
  minFare: number;
  capacity: number;
}

/**
 * Per-tier fare configuration in USD (target market: Florida, US). These are the
 * seed defaults; the live values live in the `fare_config` DB table so pricing
 * can be tuned per market without a deploy (see PricingService.seedMissing).
 * Rates are per-mile for distance and per-minute for time.
 *
 * Key order is the order riders see the tiers in, cheapest first: bike, auto,
 * then the cars. (Bike and auto are cheaper than economy per km in every market
 * we price — Pune: bike ₹10.27/km, auto ₹20/km vs the regulated ₹25/km cab
 * rate — and India's ride apps list them first the same way.)
 *
 * `bike` (bike taxi) and `auto` (auto-rickshaw) are India products with no US
 * equivalent; their USD defaults are only there so every tier has a value in
 * every market. They are economy scaled by Pune's own ratios to the regulated
 * cab per-km rate (auto 20/25 = 0.8, bike 10.27/25 ≈ 0.41). The rupee values
 * that matter are in INR_FARE_CONFIG below.
 */
export const FARE_CONFIG: Record<string, TierFareConfig> = {
  bike: {
    tier: 'bike',
    label: 'Bike',
    baseFare: 1.0,
    perMile: 0.5,
    perMin: 0.1,
    bookingFee: 1.0,
    minFare: 3.0,
    capacity: 1,
  },
  auto: {
    tier: 'auto',
    label: 'Auto',
    baseFare: 2.0,
    perMile: 0.95,
    perMin: 0.2,
    bookingFee: 1.5,
    minFare: 5.0,
    capacity: 3,
  },
  economy: {
    tier: 'economy',
    label: 'Economy',
    baseFare: 2.5,
    perMile: 1.2,
    perMin: 0.25,
    bookingFee: 2.0,
    minFare: 6.5,
    capacity: 4,
  },
  comfort: {
    tier: 'comfort',
    label: 'Comfort',
    baseFare: 3.5,
    perMile: 1.6,
    perMin: 0.35,
    bookingFee: 2.5,
    minFare: 9.0,
    capacity: 4,
  },
  xl: {
    tier: 'xl',
    label: 'XL',
    baseFare: 4.5,
    perMile: 2.2,
    perMin: 0.45,
    bookingFee: 3.0,
    minFare: 12.0,
    capacity: 6,
  },
  premium: {
    tier: 'premium',
    label: 'Premium',
    baseFare: 6.0,
    perMile: 3.0,
    perMin: 0.55,
    bookingFee: 3.5,
    minFare: 16.0,
    capacity: 4,
  },
};

export const TIER_KEYS = Object.keys(FARE_CONFIG);

/**
 * Ride types that exist (pricing, dispatch, stored trips) but are only
 * OFFERED when switched on: auto-rickshaw and bike taxi are held back by the
 * owner (2026-09-24). `EXTRA_TIERS=auto,bike` turns them on again.
 * Hidden tiers are left out of estimates and refused for new trips and
 * driver sign-ups; old rows keep reading fine.
 */
export const OPTIONAL_TIERS = ['auto', 'bike'];
export function enabledTiers(env: NodeJS.ProcessEnv = process.env): string[] {
  const extra = (env.EXTRA_TIERS ?? '')
    .split(',')
    .map((t) => t.trim())
    .filter(Boolean);
  return TIER_KEYS.filter(
    (t) => !OPTIONAL_TIERS.includes(t) || extra.includes(t),
  );
}

/** The tiers riders can book and drivers can sign up for right now. */
export const OFFERED_TIERS = enabledTiers();

/** Kilometres → miles for the per-mile columns: ₹/km × this = ₹/mile. */
const KM_PER_MILE = METERS_PER_MILE / 1000;
const perKm = (rupeesPerKm: number) => Math.round(rupeesPerKm * KM_PER_MILE * 100) / 100;

/**
 * Seed defaults for an INR market (the Pune pilot). The table is still
 * per-mile internally; the admin console shows per-km in metric markets.
 *
 * Car tiers: the pilot's own admin-set values (economy ₹12/km, comfort ₹15/km,
 * xl ₹20/km, premium ₹28/km), so a fresh INR database starts where the pilot
 * already is instead of seeding dollar numbers as rupees.
 *
 * Auto — the Pune RTA meter tariff, effective 1 Sep 2026: ₹30 for the first
 * 1.5 km, then ₹20 per km (up from ₹25 / ₹17). Modelled as ₹20/km from zero
 * with a ₹30 minimum, which reproduces the meter exactly (1.5 km × ₹20 = ₹30);
 * no base, time or booking line, so the app never quotes above the meter.
 * Source: Pune District RTA decision, reported by Pune Pulse, 1 Sep 2026
 * (mypunepulse.com, "Pune Auto Fare Hike ... Minimum Fare Increased To ₹30")
 * and The Bridge Chronicle ("Pune, PCMC Auto Rickshaw Fares to Rise from
 * September 1 as Base Fare Hiked to ₹30").
 *
 * Bike — the Maharashtra Bike Taxi Rules 2025 fare (Khatua-panel formula):
 * ₹15 for the first 1.5 km, then ₹10.27 per km. Modelled the same way:
 * ₹10.27/km from zero, ₹15 minimum (1.5 × 10.27 = ₹15.4, so the floor only
 * bites on the shortest trips). Source: Maharashtra STA provisional aggregator
 * licences, 16 Sep 2025 (Business Today, "Maharashtra STA approves bike taxi
 * services for Ola, Uber, Rapido under new rules"). Those licences name MMR;
 * the state fare is the only published rule and is what Pune aggregators quote.
 */
export const INR_FARE_CONFIG: Record<string, TierFareConfig> = {
  bike: {
    tier: 'bike',
    label: 'Bike',
    baseFare: 0,
    perMile: perKm(10.27), // 16.53
    perMin: 0,
    bookingFee: 0,
    minFare: 15,
    capacity: 1,
  },
  auto: {
    tier: 'auto',
    label: 'Auto',
    baseFare: 0,
    perMile: perKm(20), // 32.19
    perMin: 0,
    bookingFee: 0,
    minFare: 30,
    capacity: 3,
  },
  economy: {
    tier: 'economy',
    label: 'Economy',
    baseFare: 40,
    perMile: perKm(12), // 19.31
    perMin: 1,
    bookingFee: 10,
    minFare: 75,
    capacity: 4,
  },
  comfort: {
    tier: 'comfort',
    label: 'Comfort',
    baseFare: 55,
    perMile: perKm(15), // 24.14
    perMin: 1.5,
    bookingFee: 15,
    minFare: 100,
    capacity: 4,
  },
  xl: {
    tier: 'xl',
    label: 'XL',
    baseFare: 80,
    perMile: perKm(20), // 32.19
    perMin: 2,
    bookingFee: 20,
    minFare: 150,
    capacity: 6,
  },
  premium: {
    tier: 'premium',
    label: 'Premium',
    baseFare: 120,
    perMile: perKm(28), // 45.06
    perMin: 3,
    bookingFee: 25,
    minFare: 200,
    capacity: 4,
  },
};

/**
 * Build a market's tiers from its economy rates, keeping each tier's USD
 * ratio to economy (comfort/economy, xl/economy, ... from FARE_CONFIG).
 * `round` rounds each money figure the way that market quotes it.
 */
function scaledFromEconomy(
  economy: Omit<TierFareConfig, 'tier' | 'label' | 'capacity'>,
  round: (n: number) => number,
): Record<string, TierFareConfig> {
  const e = FARE_CONFIG.economy;
  const ratio = (a: number, b: number) => (b === 0 ? 1 : a / b);
  const out: Record<string, TierFareConfig> = {};
  for (const [key, t] of Object.entries(FARE_CONFIG)) {
    out[key] = {
      tier: t.tier,
      label: t.label,
      capacity: t.capacity,
      baseFare: round(economy.baseFare * ratio(t.baseFare, e.baseFare)),
      perMile: round(economy.perMile * ratio(t.perMile, e.perMile)),
      perMin: round(economy.perMin * ratio(t.perMin, e.perMin)),
      bookingFee: round(economy.bookingFee * ratio(t.bookingFee, e.bookingFee)),
      minFare: round(economy.minFare * ratio(t.minFare, e.minFare)),
    };
  }
  return out;
}

/**
 * PROVISIONAL seed fares for the final market (Tashkent, UZS; Dubai, AED).
 * These are a starting
 * point for the owner to tune (live values live in the fare_config table),
 * not a signed-off price list. Before these existed a UZS market silently
 * seeded the USD numbers labelled as so'm.
 */
export const UZS_FARE_CONFIG = scaledFromEconomy(
  {
    baseFare: 4000,
    perMile: Math.round(2200 * KM_PER_MILE), // 2,200 so'm/km
    perMin: 100,
    bookingFee: 1000,
    minFare: 9000,
  },
  (n) => Math.round(n / 100) * 100,
);

export const AED_FARE_CONFIG = scaledFromEconomy(
  {
    baseFare: 4.5,
    perMile: perKm(1.95),
    perMin: 0.25,
    bookingFee: 1,
    minFare: 12,
  },
  (n) => Math.round(n * 100) / 100,
);

/** The seed defaults for a market currency (unknown codes fall back to USD). */
export function defaultFareConfig(
  currency: string = CURRENCY,
): Record<string, TierFareConfig> {
  switch (currency.toUpperCase()) {
    case 'INR':
      return INR_FARE_CONFIG;
    case 'UZS':
      return UZS_FARE_CONFIG;
    case 'AED':
      return AED_FARE_CONFIG;
    default:
      return FARE_CONFIG;
  }
}
