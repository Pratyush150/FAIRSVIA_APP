import { Injectable } from '@nestjs/common';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { RealtimeService } from '../realtime/realtime.service';
import { LatLng } from '../geo/geo-provider.interface';
import {
  decodePolyline,
  haversineMeters,
  remainingAlongPolyline,
} from '../geo/geo.util';

/** A single GPS segment longer than this (meters) is treated as a fix jump /
 *  reconnect gap and skipped, so the odometer isn't inflated by teleports. */
const MAX_SANE_SEGMENT_M = 2000;
/** Implied ground speed above this (m/s, ~216 km/h) between two consecutive
 *  metered points is not a car — the segment is a spoofed/garbage fix and is
 *  not added to the odometer. Metering is driver-controlled input that feeds
 *  the final fare, so it must be plausibility-gated server-side. */
export const MAX_PLAUSIBLE_SPEED_MPS = 60;
/** A fix whose reported horizontal accuracy is worse than this (meters) is
 *  too noisy to meter — it can still update the driver's live position but
 *  contributes nothing to driven distance. */
export const MAX_METER_ACCURACY_M = 100;
/** A fix noisier than this is also withheld from the rider's live map — a
 *  100 m+ blob jumping around is worse than a briefly-frozen marker. */
export const MAX_BROADCAST_ACCURACY_M = 100;
/** ETA fallback pace (m/s) when the leg has no routed average speed. */
export const FALLBACK_ETA_MPS = 8;

/**
 * Atomic trip odometer step, run inside Redis so read-add-write can't interleave
 * across concurrent pings (Socket.IO doesn't serialize async handlers).
 *   KEYS[1] = trip driven-meters counter (exists only while in_progress)
 *   KEYS[2] = trip last-metered-point hash (lat, lng, ts)
 *   ARGV = lat, lng, maxSegmentMeters, nowMs, maxSpeedMps
 * No-ops unless metering is active (the counter was seeded at trip start).
 * A segment is added only when it is (a) shorter than the sane cap and (b)
 * its implied speed since the last metered point is plausible; the last point
 * is advanced regardless, so an implausible jump is dropped rather than
 * counted on the next ping.
 */
const METER_STEP_LUA = `
if redis.call('EXISTS', KEYS[1]) == 0 then return false end
local last = redis.call('HMGET', KEYS[2], 'lat', 'lng', 'ts')
local lat2 = tonumber(ARGV[1])
local lng2 = tonumber(ARGV[2])
local maxseg = tonumber(ARGV[3])
local now = tonumber(ARGV[4])
local maxspeed = tonumber(ARGV[5])
if last[1] and last[2] then
  local rad = math.pi / 180
  local lat1 = tonumber(last[1]) * rad
  local la2 = lat2 * rad
  local dLat = (lat2 - tonumber(last[1])) * rad
  local dLng = (lng2 - tonumber(last[2])) * rad
  local a = math.sin(dLat / 2) ^ 2 + math.cos(lat1) * math.cos(la2) * math.sin(dLng / 2) ^ 2
  local seg = 2 * 6371000 * math.asin(math.sqrt(a))
  local plausible = true
  if last[3] then
    local dt = (now - tonumber(last[3])) / 1000
    if dt <= 0 then
      plausible = false
    elseif seg / dt > maxspeed then
      plausible = false
    end
  end
  if plausible and seg > 0 and seg < maxseg then
    redis.call('INCRBYFLOAT', KEYS[1], seg)
  end
end
redis.call('HSET', KEYS[2], 'lat', lat2, 'lng', lng2, 'ts', now)
return redis.call('GET', KEYS[1])
`;

export interface LocationPing {
  lat: number;
  lng: number;
  heading?: number;
  speed?: number;
  /** Horizontal accuracy radius in meters, when the device reports it. */
  accuracy?: number;
  /** Device time of the fix (epoch ms), when the client sends it. */
  ts?: number;
}

/** Per-leg navigation context (Redis hash `trip:{id}:nav`). */
export interface NavContext {
  phase: 'approach' | 'trip';
  target: LatLng;
  /** Encoded route for the leg; empty when unknown. */
  polyline: string;
  /** Routed average pace for the leg (m/s); undefined when unknown. */
  avgSpeedMps?: number;
}

/** Live progress estimate carried on every `trip:driver_location`. */
export interface EtaEstimate {
  remainingM: number;
  etaSec: number;
  /** 'route' = along the stored polyline; 'straight' = haversine fallback. */
  etaSource: 'route' | 'straight';
}

/**
 * Ingests high-frequency driver GPS. Writes to Redis (never Postgres on the
 * hot path): a position hash + the tier GEO set for matching. If the driver is
 * on a trip, broadcasts the position to the rider.
 */
@Injectable()
export class LocationService {
  constructor(
    private readonly redis: RedisService,
    private readonly realtime: RealtimeService,
  ) {}

  async ingest(driverId: string, ping: LocationPing): Promise<void> {
    const { lat, lng, accuracy } = ping;
    const now = Date.now();
    // Clamp heading/speed: clients report -1 (or NaN) when unavailable (a
    // stationary driver), which we accept at the DTO but normalize here.
    const rawHeading = ping.heading ?? 0;
    const rawSpeed = ping.speed ?? 0;
    const heading =
      Number.isFinite(rawHeading) && rawHeading >= 0 && rawHeading <= 360
        ? rawHeading
        : 0;
    const speed =
      Number.isFinite(rawSpeed) && rawSpeed >= 0 && rawSpeed <= 400
        ? rawSpeed
        : 0;

    await this.redis.client.hset(RedisKeys.driverLoc(driverId), {
      lat,
      lng,
      heading,
      speed,
      // Server clock: staleness checks (dispatch eviction, arrival geofence)
      // must not trust a device clock.
      ts: now,
      ...(accuracy !== undefined ? { accuracy } : {}),
    });

    const [status, tripId] = await Promise.all([
      this.redis.client.get(RedisKeys.driverStatus(driverId)),
      this.redis.client.get(RedisKeys.driverActiveTrip(driverId)),
    ]);

    // Keep the driver in the dispatch pool only while online AND free. An
    // on-trip driver keeps streaming GPS (for the rider's live map), but must
    // NOT be re-added to the GEO set — dispatch removes them at assignment, and
    // re-adding here would offer them new trips they can't take, causing offer
    // churn and spurious no_drivers under load.
    if (status === 'online' && !tripId) {
      const tier = await this.redis.client.get(RedisKeys.driverTier(driverId));
      if (tier) {
        // ioredis geoadd: key, longitude, latitude, member
        await this.redis.client.geoadd(RedisKeys.driversGeo(tier), lng, lat, driverId);
      }
    }

    // On a trip → stream the position to the rider watching the map, with a
    // cheap live ETA for the current leg. A fix the device itself flags as
    // noisy (accuracy radius > 100 m) is neither shown to the rider (a marker
    // that jumps a block is worse than one that pauses) nor metered (it would
    // add phantom distance to the fare); it still updates the driver's stored
    // position so presence stays fresh.
    if (tripId) {
      const usable = accuracy === undefined || accuracy <= MAX_BROADCAST_ACCURACY_M;
      if (usable) {
        const [riderId, nav] = await Promise.all([
          this.redis.client.get(RedisKeys.driverActiveRider(driverId)),
          this.readNav(tripId),
        ]);
        if (riderId) {
          const eta = nav ? LocationService.estimate({ lat, lng }, nav) : undefined;
          this.realtime.emitToUser(riderId, 'trip:driver_location', {
            tripId,
            lat,
            lng,
            heading,
            speed,
            accuracy: accuracy ?? null,
            ts: ping.ts ?? now,
            phase: nav?.phase ?? null,
            etaSec: eta?.etaSec ?? null,
            remainingM: eta?.remainingM ?? null,
            etaSource: eta?.etaSource ?? null,
          });
        }
      }
      if (accuracy === undefined || accuracy <= MAX_METER_ACCURACY_M) {
        await this.meterTrip(tripId, lat, lng);
      }
    }
  }

  /** Load the leg's navigation context; null when none is stored. */
  private async readNav(tripId: string): Promise<NavContext | null> {
    const h = await this.redis.client.hgetall(RedisKeys.tripNav(tripId));
    if (!h || !h.targetLat || !h.targetLng) return null;
    const lat = Number(h.targetLat);
    const lng = Number(h.targetLng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
    const speed = Number(h.avgSpeedMps);
    return {
      phase: h.phase === 'trip' ? 'trip' : 'approach',
      target: { lat, lng },
      polyline: h.polyline ?? '',
      avgSpeedMps: Number.isFinite(speed) && speed > 0 ? speed : undefined,
    };
  }

  /**
   * Remaining distance + ETA for the leg from the driver's current point:
   * along the stored polyline at the leg's routed average speed when a route
   * is known, else straight-line to the target at FALLBACK_ETA_MPS. Pure and
   * cheap (no I/O) — runs on every ping.
   */
  static estimate(pos: LatLng, nav: NavContext): EtaEstimate {
    let remainingM: number | null = null;
    let etaSource: EtaEstimate['etaSource'] = 'straight';
    if (nav.polyline) {
      try {
        remainingM = remainingAlongPolyline(pos, decodePolyline(nav.polyline));
        if (remainingM !== null) etaSource = 'route';
      } catch {
        remainingM = null;
      }
    }
    if (remainingM === null) {
      remainingM = Math.round(haversineMeters(pos, nav.target));
    }
    const pace = nav.avgSpeedMps ?? FALLBACK_ETA_MPS;
    return {
      remainingM,
      etaSec: Math.max(0, Math.round(remainingM / pace)),
      etaSource,
    };
  }

  /**
   * Accumulates the actually-driven distance while a trip is in progress. The
   * odometer key (`trip:{id}:driven`) exists only between start and complete —
   * so pings during en-route-to-pickup are ignored. Used to recompute the
   * final fare from real distance rather than the up-front estimate.
   */
  private async meterTrip(tripId: string, lat: number, lng: number): Promise<void> {
    // One atomic EVAL: gates on active metering + plausibility (implied speed),
    // accumulates the segment, and advances the last point — immune to
    // interleaving across burst pings.
    await this.redis.client.eval(
      METER_STEP_LUA,
      2,
      RedisKeys.tripDriven(tripId),
      RedisKeys.tripMeterLast(tripId),
      lat,
      lng,
      MAX_SANE_SEGMENT_M,
      Date.now(),
      MAX_PLAUSIBLE_SPEED_MPS,
    );
  }
}
