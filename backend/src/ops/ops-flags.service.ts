import { Injectable, Logger } from '@nestjs/common';
import { RedisService } from '../common/redis/redis.service';

/**
 * The kill switches, and what each one actually does when thrown.
 *
 * Every flag is FALSE in normal operation, so "all false" is the healthy
 * state and a flag left on is visible as an anomaly rather than a default.
 */
export const OPS_FLAGS = {
  /**
   * Stop calling Google for geo and serve everything from self-hosted
   * OSRM/Nominatim. The first switch to reach for: it is what would have
   * stopped the 20,370-error quota burn in the load sweep immediately,
   * instead of after someone noticed.
   */
  geoFallbackOnly: 'Force geo off Google (use self-hosted OSRM/Nominatim)',

  /**
   * Stop matching new trips. Riders can still be quoted and can still see a
   * ride in flight; nothing new gets offered to a driver. For when dispatch
   * itself is misbehaving and offering churn is making things worse.
   */
  dispatchPaused: 'Pause dispatch (stop matching new trips)',

  /** Price every ride at 1.0x regardless of measured demand. */
  surgeDisabled: 'Disable surge pricing',

  /** Block driver withdrawals. For a suspected payout or ledger fault. */
  payoutsFrozen: 'Freeze driver payouts',
} as const;

export type OpsFlag = keyof typeof OPS_FLAGS;

export const OPS_FLAG_NAMES = Object.keys(OPS_FLAGS) as OpsFlag[];

/** Redis hash holding the flags. One key, so a read is a single round trip. */
const KEY = 'ops:flags';

/**
 * Runtime operational switches.
 *
 * Held in Redis rather than in config so a switch takes effect **immediately,
 * on every replica, without a deploy** — which is the entire point of a kill
 * switch. A flag that needs a restart to take effect is not a kill switch, it
 * is a config change.
 *
 * Reads are cached for [cacheMs] because the hot path (every geo call, every
 * dispatch) consults them; that bounds the extra Redis traffic at a few reads
 * per second while keeping the worst-case delay between flipping a switch and
 * it biting to under a second.
 *
 * Reads NEVER throw. If Redis is unreachable the flags report their safe
 * default (false, meaning "behave normally"): a monitoring dependency must not
 * be able to pause dispatch by falling over.
 */
@Injectable()
export class OpsFlagsService {
  private readonly logger = new Logger(OpsFlagsService.name);

  /** How long a read is reused before going back to Redis. */
  static readonly cacheMs = 1000;

  private cache: Record<OpsFlag, boolean> | null = null;
  private cachedAt = 0;

  constructor(private readonly redis: RedisService) {}

  /** Every flag, with false for anything unset. */
  async all(): Promise<Record<OpsFlag, boolean>> {
    const now = Date.now();
    if (this.cache && now - this.cachedAt < OpsFlagsService.cacheMs) {
      return this.cache;
    }
    const out = this.defaults();
    try {
      const raw = await this.redis.client.hgetall(KEY);
      for (const name of OPS_FLAG_NAMES) out[name] = raw?.[name] === '1';
    } catch (e) {
      // Safe default: behave normally. A Redis blip must not silently pause
      // the marketplace.
      this.logger.warn(`ops flags unreadable, assuming all off: ${String(e)}`);
      return out;
    }
    this.cache = out;
    this.cachedAt = now;
    return out;
  }

  /** Whether one flag is on. Never throws. */
  async isOn(flag: OpsFlag): Promise<boolean> {
    return (await this.all())[flag];
  }

  /**
   * Turn a flag on or off. Returns the full set afterwards.
   *
   * Throwing here is deliberate, and the opposite of [all]'s behaviour: if we
   * cannot write the switch, the operator must be told it did not take —
   * believing dispatch is paused when it is not is far worse than an error.
   */
  async set(flag: OpsFlag, on: boolean): Promise<Record<OpsFlag, boolean>> {
    await this.redis.client.hset(KEY, flag, on ? '1' : '0');
    this.cache = null; // next read goes to Redis
    this.logger.warn(`ops flag ${flag} -> ${on ? 'ON' : 'off'}`);
    return this.all();
  }

  private defaults(): Record<OpsFlag, boolean> {
    return Object.fromEntries(OPS_FLAG_NAMES.map((n) => [n, false])) as Record<
      OpsFlag,
      boolean
    >;
  }
}
