import {
  BadRequestException,
  Injectable,
  Logger,
  OnModuleInit,
} from '@nestjs/common';
import { roundFare } from '../common/money';
import { PrismaService } from '../common/prisma/prisma.service';
import {
  CURRENCY,
  FARE_CONFIG,
  METERS_PER_MILE,
  TierFareConfig,
} from './fare-config';

export interface FareBreakdown {
  /** All three ride components are reported AFTER surge, so the lines the
   *  rider is shown add up to the fare they are quoted. */
  baseFare: number;
  distanceFare: number;
  timeFare: number;
  /** Flat, never surged. */
  bookingFee: number;
  surgeMultiplier: number;
  /** Top-up applied when the metered components fell short of the tier's
   *  minimum fare (0 when they didn't), so the lines still sum to the fare. */
  minimumFareAdjustment: number;
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
export class PricingService implements OnModuleInit {
  private readonly logger = new Logger('Pricing');

  // In-memory cache of the DB fare config so the estimate methods stay
  // synchronous (they're on the hot path). Refreshed on admin edits; falls back
  // to the hardcoded defaults if the DB is somehow empty.
  private cache: Record<string, TierFareConfig> = { ...FARE_CONFIG };
  private order: string[] = Object.keys(FARE_CONFIG);

  constructor(private readonly prisma: PrismaService) {}

  async onModuleInit() {
    await this.seedIfEmpty();
    await this.refresh();
  }

  /** Seed the fare_config table from the code defaults on first boot. */
  private async seedIfEmpty() {
    const count = await this.prisma.fareConfig.count();
    if (count > 0) return;
    await this.prisma.fareConfig.createMany({
      data: Object.values(FARE_CONFIG).map((c) => ({
        tier: c.tier,
        label: c.label,
        baseFare: c.baseFare,
        perMile: c.perMile,
        perMin: c.perMin,
        bookingFee: c.bookingFee,
        minFare: c.minFare,
        capacity: c.capacity,
      })),
      skipDuplicates: true,
    });
    this.logger.log('Seeded fare_config from defaults');
  }

  /** Reload the cache from the DB. */
  async refresh() {
    try {
      const rows = await this.prisma.fareConfig.findMany();
      if (rows.length === 0) return;
      const next: Record<string, TierFareConfig> = {};
      for (const r of rows) {
        next[r.tier] = {
          tier: r.tier,
          label: r.label,
          baseFare: r.baseFare,
          perMile: r.perMile,
          perMin: r.perMin,
          bookingFee: r.bookingFee,
          minFare: r.minFare,
          capacity: r.capacity,
        };
      }
      this.cache = next;
      // Preserve the canonical tier ordering (cheapest → premium).
      this.order = Object.keys(FARE_CONFIG).filter((t) => next[t]);
    } catch (e) {
      this.logger.warn(`fare_config refresh failed, keeping cache: ${String(e)}`);
    }
  }

  /** Admin: list the current fare config. */
  listConfig(): TierFareConfig[] {
    return this.order.map((t) => this.cache[t]);
  }

  /** Admin: update one tier's fare config, then refresh the cache. */
  async updateTier(
    tier: string,
    patch: Partial<Omit<TierFareConfig, 'tier'>>,
  ): Promise<TierFareConfig> {
    if (!this.cache[tier]) {
      throw new BadRequestException(`Unknown tier: ${tier}`);
    }
    await this.prisma.fareConfig.update({
      where: { tier },
      data: {
        label: patch.label,
        baseFare: patch.baseFare,
        perMile: patch.perMile,
        perMin: patch.perMin,
        bookingFee: patch.bookingFee,
        minFare: patch.minFare,
        capacity: patch.capacity,
      },
    });
    await this.refresh();
    return this.cache[tier];
  }

  /**
   * fare = (base + perMile*mi + perMin*min) * surge + bookingFee, floored at
   * minFare. The returned breakdown always sums to `fare`: base/distance/time
   * carry the surge, the booking fee doesn't, and any shortfall against the
   * minimum fare is reported as its own line.
   */
  estimateForTier(
    tier: string,
    distanceM: number,
    durationS: number,
    surge = 1,
  ): FareEstimate {
    const cfg = this.cache[tier];
    if (!cfg) {
      throw new BadRequestException(`Unknown tier: ${tier}`);
    }
    return this.compute(cfg, distanceM, durationS, surge);
  }

  /** The configured minimum fare for a tier (the floor every fare respects). */
  minFareFor(tier: string): number {
    const cfg = this.cache[tier];
    if (!cfg) {
      throw new BadRequestException(`Unknown tier: ${tier}`);
    }
    return cfg.minFare;
  }

  /** Estimate every tier for the same trip (what the rider chooses from). */
  estimateAllTiers(
    distanceM: number,
    durationS: number,
    surge = 1,
  ): FareEstimate[] {
    return this.order.map((tier) =>
      this.compute(this.cache[tier], distanceM, durationS, surge),
    );
  }

  private compute(
    cfg: TierFareConfig,
    distanceM: number,
    durationS: number,
    surge: number,
  ): FareEstimate {
    const distanceMi = distanceM / METERS_PER_MILE;
    const durationMin = durationS / 60;

    const distanceFare = cfg.perMile * distanceMi;
    const timeFare = cfg.perMin * durationMin;

    // Round each line to cents FIRST, then total them. Rounding the lines and
    // the total independently leaves the two up to a cent apart, and a rider
    // reading the "Details" list can do the addition themselves — so the fare
    // is defined as the sum of what they are shown, floored at the minimum.
    // In whole-unit markets (₹, so'm) each line is a whole number, so the
    // total is too and the itemisation still adds up exactly.
    const r = (n: number) => roundFare(n, CURRENCY);
    const base = r(cfg.baseFare * surge);
    const distance = r(distanceFare * surge);
    const time = r(timeFare * surge);
    const booking = r(cfg.bookingFee);
    const metered = round2(base + distance + time + booking);
    const fare = Math.max(metered, r(cfg.minFare));
    const shortfall = round2(fare - metered);

    return {
      tier: cfg.tier,
      label: cfg.label,
      capacity: cfg.capacity,
      fare,
      currency: CURRENCY,
      etaSeconds: durationS,
      breakdown: {
        // Surged, so these lines and the booking fee sum to the quoted fare.
        // Reporting an un-surged base here understated the itemisation by
        // base*(surge-1) and pushed the difference into the minimum-fare line.
        baseFare: base,
        distanceFare: distance,
        timeFare: time,
        bookingFee: booking,
        surgeMultiplier: surge,
        minimumFareAdjustment: shortfall > 0 ? shortfall : 0,
      },
    };
  }
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
