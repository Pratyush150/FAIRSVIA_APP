export const CURRENCY = 'INR';

export interface TierFareConfig {
  tier: string;
  label: string;
  baseFare: number;
  perKm: number;
  perMin: number;
  bookingFee: number;
  minFare: number;
  capacity: number;
}

/**
 * Per-tier fare configuration (INR). In Phase 5 this moves to a DB table so
 * pricing can be tuned per city without a deploy.
 */
export const FARE_CONFIG: Record<string, TierFareConfig> = {
  economy: {
    tier: 'economy',
    label: 'Economy',
    baseFare: 30,
    perKm: 12,
    perMin: 1.5,
    bookingFee: 10,
    minFare: 60,
    capacity: 4,
  },
  comfort: {
    tier: 'comfort',
    label: 'Comfort',
    baseFare: 45,
    perKm: 16,
    perMin: 2,
    bookingFee: 12,
    minFare: 90,
    capacity: 4,
  },
  xl: {
    tier: 'xl',
    label: 'XL',
    baseFare: 60,
    perKm: 20,
    perMin: 2.5,
    bookingFee: 15,
    minFare: 120,
    capacity: 6,
  },
  premium: {
    tier: 'premium',
    label: 'Premium',
    baseFare: 80,
    perKm: 26,
    perMin: 3,
    bookingFee: 20,
    minFare: 160,
    capacity: 4,
  },
};

export const TIER_KEYS = Object.keys(FARE_CONFIG);
