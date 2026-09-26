import { Logger } from '@nestjs/common';
import { roundFare } from '../common/money';

/**
 * Price match: RideVela's quoted fare for a tier is never above the cheapest
 * modelled competitor for the same trip. Competitor estimates are NOT touched
 * (they stay the honest, sourced models in competitor-config.ts) — only OUR
 * fare comes down:
 *
 *   matched = min(computed, cheapestCompetitor - undercut)
 *   undercut = max(1, PRICE_MATCH_UNDERCUT_PCT% of cheapestCompetitor)
 *
 * rounded like any fare line, and never below PRICE_MATCH_FLOOR (the floor
 * wins over "cheapest", and that is logged).
 *
 * Env: PRICE_MATCH_ENABLED (default true), PRICE_MATCH_UNDERCUT_PCT
 * (default 3), PRICE_MATCH_FLOOR (default 30, market currency units).
 */
export interface PriceMatchConfig {
  enabled: boolean;
  undercutPct: number;
  floor: number;
}

export function priceMatchConfig(env: NodeJS.ProcessEnv = process.env): PriceMatchConfig {
  const num = (v: string | undefined, d: number) => {
    const n = v === undefined || v.trim() === '' ? NaN : Number(v);
    return Number.isFinite(n) && n >= 0 ? n : d;
  };
  const flag = (env.PRICE_MATCH_ENABLED ?? 'true').trim().toLowerCase();
  return {
    enabled: !['false', '0', 'no', 'off'].includes(flag),
    undercutPct: num(env.PRICE_MATCH_UNDERCUT_PCT, 3),
    floor: num(env.PRICE_MATCH_FLOOR, 30),
  };
}

export interface PriceMatchResult {
  /** The fare we quote/charge. */
  fare: number;
  /** Our fare before the match. */
  computedFare: number;
  /** True when the match lowered our fare. */
  applied: boolean;
  /** True when the floor stopped us from undercutting the cheapest competitor. */
  floorBlocked: boolean;
}

const logger = new Logger('PriceMatch');

export function applyPriceMatch(
  computedFare: number,
  competitorPrices: number[],
  currency: string,
  cfg: PriceMatchConfig = priceMatchConfig(),
): PriceMatchResult {
  const none = { fare: computedFare, computedFare, applied: false, floorBlocked: false };
  if (!cfg.enabled || competitorPrices.length === 0) return none;
  const cheapest = Math.min(...competitorPrices);
  const undercut = Math.max(1, (cheapest * cfg.undercutPct) / 100);
  // Round DOWN to the fare unit so rounding can never land us on/above them.
  const unit = roundFare(0.4, currency) === 0 ? 1 : 0.01;
  const target = Math.floor((cheapest - undercut) / unit + 1e-9) * unit;
  if (computedFare <= target) return none;
  let fare = roundFare(target, currency);
  let floorBlocked = false;
  if (fare < cfg.floor) {
    fare = Math.min(computedFare, roundFare(cfg.floor, currency));
    floorBlocked = fare >= cheapest;
    if (floorBlocked) {
      logger.warn(
        `price match floor ${cfg.floor} ${currency} kept our fare (${fare}) at/above the cheapest competitor (${cheapest})`,
      );
    }
  }
  return { fare, computedFare, applied: fare < computedFare, floorBlocked };
}
