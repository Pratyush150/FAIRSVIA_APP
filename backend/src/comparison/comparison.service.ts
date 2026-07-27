import { Injectable } from '@nestjs/common';
import { PricingService } from '../pricing/pricing.service';
import { CURRENCY, METERS_PER_MILE } from '../pricing/fare-config';
import { COMPETITOR_MODELS, ProviderFareModel } from './competitor-config';

/** A single provider's price for the trip (ours or a modeled competitor). */
export interface ProviderQuote {
  provider: string;
  displayName: string;
  productName: string;
  price: number;
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
  /** Plain-language honesty note surfaced to the client. */
  disclaimer: string;
}

const OUR_PROVIDER = 'ubernav';
const OUR_DISPLAY = 'UberNav';

export const COMPARISON_DISCLAIMER =
  'Competitor prices are estimates modeled from each provider’s published fare ' +
  'rates for this trip’s distance and time — not live quotes. Actual Uber, Lyft, ' +
  'and Empower prices vary with real-time demand.';

@Injectable()
export class ComparisonService {
  constructor(private readonly pricing: PricingService) {}

  /**
   * Compare our fare against every modeled competitor for a routed trip.
   *
   * Pure given (distanceM, durationS, surge, tier): our price comes from the
   * real PricingService; competitor prices are modeled from their rate cards.
   * The caller supplies distance/duration (already routed) so this does no I/O.
   */
  compare(
    distanceM: number,
    durationS: number,
    surge = 1,
    tier = 'economy',
    models: ProviderFareModel[] = COMPETITOR_MODELS,
  ): PriceComparison {
    const distanceMi = distanceM / METERS_PER_MILE;
    const durationMin = durationS / 60;

    // Our real price for the chosen tier.
    const ourEstimate = this.pricing.estimateForTier(
      tier,
      distanceM,
      durationS,
      surge,
    );
    const ourQuote: ProviderQuote = {
      provider: OUR_PROVIDER,
      displayName: OUR_DISPLAY,
      productName: ourEstimate.label,
      price: ourEstimate.fare,
      currency: CURRENCY,
      isOurs: true,
      estimated: false,
    };

    const competitorQuotes: ProviderQuote[] = models.map((m) => ({
      provider: m.provider,
      displayName: m.displayName,
      productName: m.productName,
      price: modelCompetitorFare(m, distanceMi, durationMin, surge),
      currency: CURRENCY,
      isOurs: false,
      estimated: true,
    }));

    const quotes = [ourQuote, ...competitorQuotes].sort(
      (a, b) => a.price - b.price,
    );

    const cheapest = quotes[0];
    const rank = quotes.findIndex((q) => q.isOurs) + 1;
    const priciest = quotes[quotes.length - 1];

    const vs: ProviderDelta[] = competitorQuotes.map((q) => ({
      provider: q.provider,
      displayName: q.displayName,
      diff: round2(ourQuote.price - q.price),
      pct: q.price === 0 ? 0 : round1(((ourQuote.price - q.price) / q.price) * 100),
    }));

    return {
      tier,
      distanceM,
      durationS,
      distanceMi: round2(distanceMi),
      durationMin: round1(durationMin),
      surge,
      currency: CURRENCY,
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
        maxSavings: round2(Math.max(0, priciest.price - ourQuote.price)),
        vs,
      },
      disclaimer: COMPARISON_DISCLAIMER,
    };
  }
}

/**
 * fare = (base + perMile*mi + perMin*min) * effectiveSurge + bookingFee,
 * floored at minFare. effectiveSurge dampens/amplifies our surge per the
 * provider's modeled sensitivity.
 */
function modelCompetitorFare(
  m: ProviderFareModel,
  distanceMi: number,
  durationMin: number,
  surge: number,
): number {
  const effectiveSurge = 1 + (surge - 1) * m.surgeSensitivity;
  const metered =
    (m.baseFare + m.perMile * distanceMi + m.perMin * durationMin) *
    effectiveSurge;
  return round2(Math.max(metered + m.bookingFee, m.minFare));
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

function round1(n: number): number {
  return Math.round(n * 10) / 10;
}
