import { Injectable } from '@nestjs/common';
import { RedisService } from '../common/redis/redis.service';
import { OpsFlagsService } from '../ops/ops-flags.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { TIER_KEYS } from '../pricing/fare-config';

/** ~2.2 km grid cell for demand aggregation. */
const CELL_DEG = 0.02;
/** Demand window: a rider's live request "counts" toward surge for this long. */
export const DEMAND_TTL = 300;
/**
 * Supply search radius around the pickup. Must match dispatch's MAX_RADIUS_KM:
 * a driver dispatch will actually reach IS available supply. With a smaller
 * radius the only online driver sitting at, say, 7 km counted as zero supply
 * and every rider was quoted the surge cap while a car was on its way to them.
 */
const SUPPLY_RADIUS_KM = 9;
/** Hard ceiling on the surge multiplier. */
export const SURGE_CAP = 2.0;

/**
 * Demand/supply surge engine. Demand = recent ride requests in a pickup cell;
 * supply = online drivers within a few km. The ratio maps to a stepped
 * multiplier (1.0–2.0). An admin can force a global floor via an override.
 */
@Injectable()
export class SurgeService {
  constructor(
    private readonly redis: RedisService,
    private readonly flags: OpsFlagsService,
  ) {}

  private cell(lat: number, lng: number): string {
    return `${Math.round(lat / CELL_DEG)}:${Math.round(lng / CELL_DEG)}`;
  }

  /**
   * Record a rider's live request as local demand. The cell holds a SET of
   * rider ids, so one rider re-requesting (retries, cancel-and-rebook, a
   * PRICE_CHANGED re-confirm) never counts more than once per window — a
   * counter here let a single rider surge their own cell to 2.0x.
   */
  async recordDemand(lat: number, lng: number, riderId: string): Promise<void> {
    const key = RedisKeys.surgeDemand(this.cell(lat, lng));
    await this.redis.client.sadd(key, riderId);
    await this.redis.client.expire(key, DEMAND_TTL);
  }

  /**
   * Withdraw a rider's demand when their request ends without a ride
   * (cancelled / no_drivers): unmet demand must not keep pricing the next
   * rider up. No-op if the window already expired.
   */
  async releaseDemand(lat: number, lng: number, riderId: string): Promise<void> {
    await this.redis.client.srem(
      RedisKeys.surgeDemand(this.cell(lat, lng)),
      riderId,
    );
  }

  /** Current surge multiplier for a pickup (>= admin override). */
  async multiplierFor(lat: number, lng: number): Promise<number> {
    // Kill switch: price everything at 1.0x regardless of measured demand.
    // Checked before the demand/supply reads so throwing it also sheds their
    // Redis load.
    if (await this.flags.isOn('surgeDisabled')) return 1;
    const [demand, supply, override] = await Promise.all([
      this.demandAt(lat, lng),
      this.supplyAt(lat, lng),
      this.override(),
    ]);
    return Math.max(this.curve(demand, supply), override);
  }

  private async demandAt(lat: number, lng: number): Promise<number> {
    return this.redis.client.scard(RedisKeys.surgeDemand(this.cell(lat, lng)));
  }

  private async supplyAt(lat: number, lng: number): Promise<number> {
    let total = 0;
    for (const tier of TIER_KEYS) {
      const res = await this.redis.client.geosearch(
        RedisKeys.driversGeo(tier),
        'FROMLONLAT',
        lng,
        lat,
        'BYRADIUS',
        SUPPLY_RADIUS_KM,
        'km',
        'ASC',
      );
      total += Array.isArray(res) ? res.length : 0;
    }
    return total;
  }

  /**
   * Stepped demand:supply curve — legible surge tiers rather than a raw ratio.
   *
   * Surge means "more riders than cars", so it only starts once demand
   * genuinely exceeds supply: a balanced 1:1 area is not surged. With no
   * reachable driver at all the request is about to fail with "no drivers",
   * so quoting a scarcity price the rider can never use would only mislead.
   */
  private curve(demand: number, supply: number): number {
    if (demand <= 0) return 1;
    if (supply <= 0) return 1;
    const ratio = demand / supply;
    if (ratio >= 3) return SURGE_CAP;
    if (ratio >= 2) return 1.5;
    if (ratio >= 1.5) return 1.3;
    if (ratio > 1) return 1.2;
    return 1;
  }

  async override(): Promise<number> {
    const v = await this.redis.client.get(RedisKeys.surgeOverride());
    const n = v ? Number(v) : 1;
    return Number.isFinite(n) && n >= 1 ? Math.min(n, SURGE_CAP) : 1;
  }

  /** Admin: set (>=1) or clear (<=1) the global surge floor. */
  async setOverride(multiplier: number): Promise<{ override: number }> {
    const clamped = Math.min(Math.max(multiplier, 1), SURGE_CAP);
    if (clamped <= 1) {
      await this.redis.client.del(RedisKeys.surgeOverride());
      return { override: 1 };
    }
    await this.redis.client.set(RedisKeys.surgeOverride(), String(clamped));
    return { override: clamped };
  }

  /** Admin view: active demand cells with their computed multiplier. */
  async snapshot() {
    const keys = await this.redis.client.keys(
      RedisKeys.surgeDemand('*'),
    );
    const override = await this.override();
    const cells = await Promise.all(
      keys.map(async (k) => {
        const cell = k.replace('surge:demand:', '');
        const demand = await this.redis.client.scard(k);
        return { cell, demand };
      }),
    );
    return {
      override,
      cap: SURGE_CAP,
      activeCells: cells.sort((a, b) => b.demand - a.demand),
    };
  }
}
