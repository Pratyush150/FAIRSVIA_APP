import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';

/** Grid for the busy-areas map: ~1.1 km cells (0.01°). */
export const DEMAND_CELL_DEG = 0.01;
/** How far back ride requests count as "recent demand". */
export const DEMAND_WINDOW_MIN = 60;
/** Search box half-size around the driver (~11 km). */
const DEMAND_SPAN_DEG = 0.1;
/** A cell needs at least this many requests to be shown: a lone request
 *  would pin one rider's pickup on every driver's map. */
export const DEMAND_MIN_COUNT = 2;
/** Most cells returned — the map stays calm. */
const DEMAND_MAX_CELLS = 12;
/** Shared per-area cache: every driver near the same place reads one result. */
const DEMAND_CACHE_SECS = 60;
/** Cache areas are coarse (0.05° ≈ 5.5 km) so nearby drivers share them. */
const AREA_DEG = 0.05;

export interface DemandCell {
  lat: number;
  lng: number;
  count: number;
  /** 0–1, relative to the busiest cell returned. */
  intensity: number;
}

/**
 * "Busy areas" for the driver map: recent ride requests (any outcome — an
 * unmet request is exactly the demand a driver wants to see) counted on a
 * ~1 km grid around the driver. Aggregates only; never a pickup point.
 *
 * Postgres is the right read here: it is one indexed aggregate a minute per
 * area (cached in Redis), not a hot-path GPS write.
 */
@Injectable()
export class DemandMapService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  async around(lat: number, lng: number): Promise<{ windowMinutes: number; cells: DemandCell[] }> {
    const ay = Math.round(lat / AREA_DEG);
    const ax = Math.round(lng / AREA_DEG);
    const key = RedisKeys.demandMap(`${ay}:${ax}`);
    try {
      const hit = await this.redis.client.get(key);
      if (hit) return JSON.parse(hit);
    } catch {
      /* cache is optional */
    }
    const since = new Date(Date.now() - DEMAND_WINDOW_MIN * 60_000);
    const cLat = ay * AREA_DEG;
    const cLng = ax * AREA_DEG;
    const rows = await this.prisma.$queryRaw<{ y: number; x: number; n: number }[]>(Prisma.sql`
      SELECT round(pickup_lat / ${DEMAND_CELL_DEG})::int AS y,
             round(pickup_lng / ${DEMAND_CELL_DEG})::int AS x,
             count(*)::int AS n
        FROM trips
       WHERE requested_at >= ${since}
         AND pickup_lat BETWEEN ${cLat - DEMAND_SPAN_DEG} AND ${cLat + DEMAND_SPAN_DEG}
         AND pickup_lng BETWEEN ${cLng - DEMAND_SPAN_DEG} AND ${cLng + DEMAND_SPAN_DEG}
       GROUP BY 1, 2
      HAVING count(*) >= ${DEMAND_MIN_COUNT}
       ORDER BY n DESC
       LIMIT ${DEMAND_MAX_CELLS}`);
    const result = { windowMinutes: DEMAND_WINDOW_MIN, cells: toCells(rows) };
    try {
      await this.redis.client.set(key, JSON.stringify(result), 'EX', DEMAND_CACHE_SECS);
    } catch {
      /* cache is optional */
    }
    return result;
  }
}

/** Grid rows → cell centres with a 0–1 intensity (busiest = 1). */
export function toCells(rows: { y: number; x: number; n: number }[]): DemandCell[] {
  const max = rows.reduce((m, r) => Math.max(m, Number(r.n)), 0);
  if (max <= 0) return [];
  return rows.map((r) => ({
    lat: round6(Number(r.y) * DEMAND_CELL_DEG),
    lng: round6(Number(r.x) * DEMAND_CELL_DEG),
    count: Number(r.n),
    intensity: Math.round((Number(r.n) / max) * 100) / 100,
  }));
}

function round6(n: number): number {
  return Math.round(n * 1e6) / 1e6;
}
