/**
 * Competitor fare MODELS for the price-comparison feature.
 *
 * ── Honesty note (read this) ────────────────────────────────────────────────
 * Uber, Lyft, and Empower do NOT expose a public real-time pricing API:
 *   • Uber retired its public Price Estimates API in 2019 (partner-only since).
 *   • Lyft shut down its public developer API.
 *   • Empower is driver-owned (drivers set their own fares); it has no API.
 * Scraping their apps would violate their Terms of Service.
 *
 * So these are NOT live quotes. Each competitor price is *modeled* from that
 * company's PUBLISHED rate card (base + per-mile + per-minute + booking/service
 * fee + trip minimum) applied to the same distance/time we route for our own
 * trip. Every modeled quote is flagged `estimated: true` and the API response
 * carries a disclaimer, so a rider is never misled into thinking it's a live
 * Uber/Lyft price.
 *
 * These are approximations for the Miami / South-Florida market and are meant to
 * be tuned. When a real partner/live pricing integration becomes available it
 * can be dropped in behind the same {@link ProviderFareModel} shape (or the
 * service can call it instead of `compute`) without touching callers.
 *
 * Sources: each provider's public "how pricing works" / fare-estimate pages,
 * Miami market, sampled 2026-07. Treat as reference, not gospel.
 */

export interface ProviderFareModel {
  /** Stable machine id, e.g. 'uber'. */
  provider: string;
  /** Human label, e.g. 'Uber'. */
  displayName: string;
  /** The comparable product tier, e.g. 'UberX'. Shown for context. */
  productName: string;
  baseFare: number;
  perMile: number;
  perMin: number;
  /** Booking / service fee added after the metered portion. */
  bookingFee: number;
  /** Trip minimum — the fare is floored at this. */
  minFare: number;
  /**
   * How strongly this provider's price reacts to demand relative to our own
   * surge multiplier. 1.0 = same as us; >1 = surges harder (Uber/Lyft
   * "primetime"); 0 = flat, ignores surge (Empower drivers set fixed prices).
   * Applied as: effectiveSurge = 1 + (ourSurge - 1) * surgeSensitivity.
   */
  surgeSensitivity: number;
}

/**
 * Standard economy-class comparison set (UberX / Lyft Standard / Empower).
 * Kept parallel to our own `economy` tier so the comparison is like-for-like.
 */
export const COMPETITOR_MODELS: ProviderFareModel[] = [
  {
    provider: 'uber',
    displayName: 'Uber',
    productName: 'UberX',
    baseFare: 2.55,
    perMile: 1.15,
    perMin: 0.24,
    bookingFee: 2.9,
    minFare: 8.5,
    surgeSensitivity: 1.15,
  },
  {
    provider: 'lyft',
    displayName: 'Lyft',
    productName: 'Standard',
    baseFare: 1.9,
    perMile: 1.05,
    perMin: 0.22,
    bookingFee: 3.3,
    minFare: 7.5,
    surgeSensitivity: 1.1,
  },
  {
    provider: 'empower',
    displayName: 'Empower',
    productName: 'Standard',
    // Empower takes no per-ride commission (drivers pay a flat subscription),
    // so street prices trend lower and effectively flat (no surge engine).
    baseFare: 1.5,
    perMile: 0.95,
    perMin: 0.18,
    bookingFee: 0.0,
    minFare: 6.0,
    surgeSensitivity: 0.0,
  },
];
