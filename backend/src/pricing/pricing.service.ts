import { BadRequestException, Injectable } from '@nestjs/common';
import { CURRENCY, FARE_CONFIG, TIER_KEYS, TierFareConfig } from './fare-config';

export interface FareBreakdown {
  baseFare: number;
  distanceFare: number;
  timeFare: number;
  bookingFee: number;
  surgeMultiplier: number;
}

export interface FareEstimate {
  tier: string;
  label: string;
  capacity: number;
  fare: number;
  currency: string;
  etaSeconds: number;
  breakdown: FareBreakdown;
}

@Injectable()
export class PricingService {
  /**
   * fare = (base + perKm*km + perMin*min) * surge + bookingFee, floored at minFare.
   */
  estimateForTier(
    tier: string,
    distanceM: number,
    durationS: number,
    surge = 1,
  ): FareEstimate {
    const cfg = FARE_CONFIG[tier];
    if (!cfg) {
      throw new BadRequestException(`Unknown tier: ${tier}`);
    }
    return this.compute(cfg, distanceM, durationS, surge);
  }

  /** Estimate every tier for the same trip (what the rider chooses from). */
  estimateAllTiers(
    distanceM: number,
    durationS: number,
    surge = 1,
  ): FareEstimate[] {
    return TIER_KEYS.map((tier) =>
      this.compute(FARE_CONFIG[tier], distanceM, durationS, surge),
    );
  }

  private compute(
    cfg: TierFareConfig,
    distanceM: number,
    durationS: number,
    surge: number,
  ): FareEstimate {
    const distanceKm = distanceM / 1000;
    const durationMin = durationS / 60;

    const distanceFare = cfg.perKm * distanceKm;
    const timeFare = cfg.perMin * durationMin;
    const preFare = (cfg.baseFare + distanceFare + timeFare) * surge;
    const total = Math.max(preFare + cfg.bookingFee, cfg.minFare);

    return {
      tier: cfg.tier,
      label: cfg.label,
      capacity: cfg.capacity,
      fare: round2(total),
      currency: CURRENCY,
      etaSeconds: durationS,
      breakdown: {
        baseFare: round2(cfg.baseFare),
        distanceFare: round2(distanceFare * surge),
        timeFare: round2(timeFare * surge),
        bookingFee: round2(cfg.bookingFee),
        surgeMultiplier: surge,
      },
    };
  }
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
