import { Injectable } from '@nestjs/common';
import { PricingService } from '../pricing/pricing.service';
import { CURRENCY, METERS_PER_MILE } from '../pricing/fare-config';
import { roundFare } from '../common/money';
import {
  COMPETITOR_MODELS_BY_CURRENCY,
  ProviderFareModel,
} from './competitor-config';

/** True when we hold a competitor set for this currency (USD, UZS, AED). */
export function hasComparisonFor(currency: string): boolean {
  return (COMPETITOR_MODELS_BY_CURRENCY[currency.toUpperCase()]?.length ?? 0) > 0;
}
import { CalibrationService } from './calibration.service';
import { BRAND_NAME } from '../common/brand';

/** How sure we are of a modeled price. `exact` = our own real fare. */
export type QuoteConfidence = 'exact' | 'high' | 'medium' | 'low';

/** A single provider's price for the trip (ours or a modeled competitor). */
export interface ProviderQuote {
  provider: string;
  displayName: string;
  productName: string;
  price: number;
  /** Low/high band around a modeled price (equals `price` for our exact fare). */
  priceLow: number;
  priceHigh: number;
  confidence: QuoteConfidence;
  currency: string;
  /** True for our own price. */
  isOurs: boolean;
  /**
   * True when the price is MODELED from a published rate card rather than a
   * live quote. Always true for competitors, false for us (we compute our own
   * real fare). Riders must see this so they aren't misled.
   */
  estimated: boolean;
}

/** How our price stacks up against one competitor. Negative = we're cheaper. */
export interface ProviderDelta {
  provider: string;
  displayName: string;
  /** ourPrice - theirPrice (negative means we're cheaper by |diff|). */
  diff: number;
  /** diff as a % of their price (negative = we're cheaper by that %). */
  pct: number;
}

export interface PriceComparison {
  tier: string;
  distanceM: number;
  durationS: number;
  distanceMi: number;
  durationMin: number;
  surge: number;
  currency: string;
  /** All quotes, cheapest first. */
  quotes: ProviderQuote[];
  /** The minimum-price provider across the whole set (the headline answer). */
  cheapest: { provider: string; displayName: string; price: number };
  /** Our standing in the comparison. */
  ours: {
    provider: string;
    price: number;
    /** 1-based rank among all quotes (1 = cheapest). */
    rank: number;
    isCheapest: boolean;
    /** Biggest saving a rider gets by choosing us vs any pricier option (>= 0). */
    maxSavings: number;
    /** Per-competitor deltas. */
    vs: ProviderDelta[];
  };
  /** True when demand (our surge proxy) is high enough that modeled competitor
   *  prices are less reliable and likely higher — the UI flags this. */
  demandHigh: boolean;

  /** Plain-language honesty note surfaced to the client. */
  disclaimer: string;
}

const OUR_PROVIDER = 'ubernav';
const OUR_DISPLAY = BRAND_NAME;

/** Surge at/above this is treated as "high demand" for the reliability flag. */
const HIGH_DEMAND_SURGE = 1.2;

export const COMPARISON_DISCLAIMER =
  'Estimates from published fares. Other providers’ prices are modeled from ' +
  'their published rates for this trip’s distance and time — not live quotes. ' +
  'Their actual prices vary with real-time demand, tolls and route.';

@Injectable()
export class ComparisonService {
  constructor(
    private readonly pricing: PricingService,
    private readonly calibration: CalibrationService,
  ) {}

  /**
   * Compare our fare against every modeled competitor for a routed trip.
   *
   * Pure given (distanceM, durationS, surge, tier): our price comes from the
   * real PricingService; competitor prices are modeled from their (calibrated)
   * rate cards. The caller supplies distance/duration (already routed) so this
   * does no I/O. `models` defaults to the live calibrated set; tests may inject
   * a fixed set.
   */
  compare(
    distanceM: number,
    durationS: number,
    surge = 1,
    tier = 'economy',
    models?: ProviderFareModel[],
    currency: string = CURRENCY,
  ): PriceComparison {
    currency = currency.toUpperCase();
    // Calibration samples were gathered for the US set only; other markets use
    // their seeded published-rate models until they have samples of their own.
    const set =
      models ??
      (currency === 'USD'
        ? this.calibration.models()
        : COMPETITOR_MODELS_BY_CURRENCY[currency] ?? []);
    const distanceMi = distanceM / METERS_PER_MILE;
    const distanceKm = distanceM / 1000;
    const durationMin = durationS / 60;

    // Our real price for the chosen tier, in the SAME currency as the set.
    const ourEstimate = this.pricing.estimateForTierInCurrency(
      tier,
      distanceM,
      durationS,
      surge,
      currency,
    );
    const ourQuote: ProviderQuote = {
      provider: OUR_PROVIDER,
      displayName: OUR_DISPLAY,
      productName: ourEstimate.label,
      price: ourEstimate.fare,
      // Our own fare is exact — no band.
      priceLow: ourEstimate.fare,
      priceHigh: ourEstimate.fare,
      confidence: 'exact',
      currency,
      isOurs: true,
      estimated: false,
    };

    const r = (n: number) => roundFare(n, currency);
    const competitorQuotes: ProviderQuote[] = set.map((m) => {
      const price = r(
        modelCompetitorFare(m, distanceMi, durationMin, surge, distanceKm),
      );
      // Uncertainty = calibration residual (how well the model fits real fares)
      // + a surge term (we're GUESSING their surge; the guess widens the band as
      // demand rises, and only for providers that actually surge).
      const baseUnc = m.residualPct != null && m.residualPct > 0
        ? clamp(m.residualPct, 0.02, 0.1)
        : 0.06;
      const surgeUnc =
        Math.max(0, surge - 1) * 0.4 * Math.min(1, m.surgeSensitivity);
      const unc = clamp(baseUnc + surgeUnc, 0, 0.6);
      return {
        provider: m.provider,
        displayName: m.displayName,
        productName: m.productName,
        price,
        priceLow: r(price * (1 - unc)),
        priceHigh: r(price * (1 + unc)),
        confidence: unc < 0.05 ? 'high' : unc < 0.12 ? 'medium' : 'low',
        currency,
        isOurs: false,
        estimated: true,
      };
    });

    const quotes = [ourQuote, ...competitorQuotes].sort(
      (a, b) => a.price - b.price,
    );

    const cheapest = quotes[0];
    const rank = quotes.findIndex((q) => q.isOurs) + 1;
    const priciest = quotes[quotes.length - 1];

    const vs: ProviderDelta[] = competitorQuotes.map((q) => ({
      provider: q.provider,
      displayName: q.displayName,
      diff: r(ourQuote.price - q.price),
      pct: q.price === 0 ? 0 : round1(((ourQuote.price - q.price) / q.price) * 100),
    }));

    return {
      tier,
      distanceM,
      durationS,
      distanceMi: round2(distanceMi),
      durationMin: round1(durationMin),
      surge,
      currency,
      quotes,
      cheapest: {
        provider: cheapest.provider,
        displayName: cheapest.displayName,
        price: cheapest.price,
      },
      ours: {
        provider: OUR_PROVIDER,
        price: ourQuote.price,
        rank,
        isCheapest: cheapest.isOurs,
        maxSavings: r(Math.max(0, priciest.price - ourQuote.price)),
        vs,
      },
      demandHigh: surge >= HIGH_DEMAND_SURGE,
      disclaimer: COMPARISON_DISCLAIMER,
    };
  }
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, n));
}

/**
 * fare = (base + perMile*mi + perMin*min) * effectiveSurge + bookingFee,
 * floored at minFare. effectiveSurge dampens/amplifies our surge per the
 * provider's modeled sensitivity.
 */
export function modelCompetitorFare(
  m: ProviderFareModel,
  distanceMi: number,
  durationMin: number,
  surge: number,
  distanceKm = distanceMi * (METERS_PER_MILE / 1000),
): number {
  const effectiveSurge = 1 + (surge - 1) * m.surgeSensitivity;
  const metered =
    (m.baseFare +
      m.perMile * distanceMi +
      (m.perKm ?? 0) * distanceKm +
      m.perMin * durationMin) *
    effectiveSurge;
  return round2(Math.max(metered + m.bookingFee, m.minFare));
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

function round1(n: number): number {
  return Math.round(n * 10) / 10;
}
