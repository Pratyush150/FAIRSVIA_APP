export const CURRENCY = 'USD';

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
 * can be tuned per market without a deploy (see PricingService.seedIfEmpty).
 * Rates are per-mile for distance and per-minute for time.
 */
export const FARE_CONFIG: Record<string, TierFareConfig> = {
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
