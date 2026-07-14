import { Injectable } from '@nestjs/common';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { TIER_KEYS } from '../pricing/fare-config';

/** ~2.2 km grid cell for demand aggregation. */
const CELL_DEG = 0.02;
/** Demand counter lifetime (a request "counts" toward surge for this long). */
const DEMAND_TTL = 300;
/** Supply search radius around the pickup. */
const SUPPLY_RADIUS_KM = 3;
/** Hard ceiling on the surge multiplier. */
export const SURGE_CAP = 2.0;

/**
 * Demand/supply surge engine. Demand = recent ride requests in a pickup cell;
 * supply = online drivers within a few km. The ratio maps to a stepped
 * multiplier (1.0–2.0). An admin can force a global floor via an override.
 */
@Injectable()
export class SurgeService {
  constructor(private readonly redis: RedisService) {}

  private cell(lat: number, lng: number): string {
    return `${Math.round(lat / CELL_DEG)}:${Math.round(lng / CELL_DEG)}`;
  }

  /** Record a ride request's contribution to local demand. */
  async recordDemand(lat: number, lng: number): Promise<void> {
    const key = RedisKeys.surgeDemand(this.cell(lat, lng));
    await this.redis.client.incr(key);
    await this.redis.client.expire(key, DEMAND_TTL);
  }

  /** Current surge multiplier for a pickup (>= admin override). */
  async multiplierFor(lat: number, lng: number): Promise<number> {
    const [demand, supply, override] = await Promise.all([
      this.demandAt(lat, lng),
      this.supplyAt(lat, lng),
      this.override(),
    ]);
    return Math.max(this.curve(demand, supply), override);
  }

  private async demandAt(lat: number, lng: number): Promise<number> {
    const v = await this.redis.client.get(
      RedisKeys.surgeDemand(this.cell(lat, lng)),
    );
    return v ? Number(v) : 0;
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

  /** Stepped demand:supply curve — legible surge tiers rather than a raw ratio. */
  private curve(demand: number, supply: number): number {
    if (demand <= 0) return 1;
    if (supply <= 0) return SURGE_CAP;
    const ratio = demand / supply;
    if (ratio >= 3) return SURGE_CAP;
    if (ratio >= 2) return 1.5;
    if (ratio >= 1.2) return 1.3;
    if (ratio >= 0.8) return 1.2;
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
        const demand = Number((await this.redis.client.get(k)) ?? 0);
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
