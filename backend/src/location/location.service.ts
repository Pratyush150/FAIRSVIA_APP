import { Inject, Injectable, Logger } from '@nestjs/common';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { RealtimeService } from '../realtime/realtime.service';
import { NotificationsService } from '../notifications/notifications.service';
import { GEO_PROVIDER, GeoProvider, LatLng } from '../geo/geo-provider.interface';
import {
  decodePolyline,
  haversineMeters,
  projectOntoPolyline,
  remainingAlongPolyline,
} from '../geo/geo.util';
import { routeThrough } from '../trips/route-through';

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

// ---------------------------------------------------------------------------
// Rider-facing watchdogs on the driver's GPS stream.
//
// Two things a rider on board wants to be told without having to stare at the
// map: the driver has left the route, and the driver has stopped moving. Both
// are derived here rather than in the app because the server is the only place
// that sees every fix — the rider's app may be backgrounded, on a dead socket,
// or freshly reinstalled, and it must not have to keep its own history to
// notice. Each alert fires once per episode (Redis flag claimed with HSETNX, so
// concurrent pings can't double-fire) and re-arms only after the condition
// clears, which is what keeps this from becoming a popup machine.
// ---------------------------------------------------------------------------

/** Perpendicular distance off the drawn route that counts as a deviation. */
export const OFF_ROUTE_M = Number(process.env.OFF_ROUTE_M ?? 120);
/** Within this distance of the next stop, the car has reached it. */
export const STOP_REACHED_M = 80;
/** Back within this of the route counts as back on track. The gap between the
 *  two thresholds is hysteresis: a driver straddling one line would otherwise
 *  alert, clear and re-alert every few seconds. */
export const OFF_ROUTE_CLEAR_M = Number(process.env.OFF_ROUTE_CLEAR_M ?? 60);
/** Consecutive deviating fixes before alerting — one wild fix is GPS noise,
 *  not a wrong turn, and must never pop a dialog mid-ride. */
export const OFF_ROUTE_PINGS = Number(process.env.OFF_ROUTE_PINGS ?? 3);
/** Movement under this between fixes isn't going anywhere (GPS jitter while
 *  parked easily covers 10–20 m). */
export const STOPPED_RADIUS_M = Number(process.env.STOPPED_RADIUS_M ?? 50);
/** Stationary for this long → tell the rider. Long enough that ordinary
 *  traffic lights and junction queues stay silent. */
export const STOPPED_AFTER_S = Number(process.env.STOPPED_AFTER_S ?? 180);
/** Minimum gap between recomputes of the live route, so a driver genuinely
 *  off-course costs at most one routing call per window, not one per ping. */
export const REROUTE_MIN_GAP_S = Number(process.env.REROUTE_MIN_GAP_S ?? 30);
/** Watchdog state outlives any single trip leg but must not leak. */
const WATCH_TTL_S = 6 * 60 * 60;

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
  /** Intermediate stops still ahead on this leg, in order (none if unset). */
  waypoints?: LatLng[];
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
  private readonly logger = new Logger('Location');

  constructor(
    private readonly redis: RedisService,
    private readonly realtime: RealtimeService,
    private readonly notifications: NotificationsService,
    @Inject(GEO_PROVIDER) private readonly geo: GeoProvider,
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
        if (nav) await this.passReachedStop(tripId, { lat, lng }, nav);
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
          // Deviation / stopped watchdogs. Never allowed to break the GPS
          // stream: a rider's live map matters more than an advisory alert.
          await this.watch(tripId, riderId, { lat, lng }, nav, now).catch((e) =>
            this.logger.warn(`trip watch failed for ${tripId}: ${String(e)}`),
          );
        }
      }
      if (accuracy === undefined || accuracy <= MAX_METER_ACCURACY_M) {
        await this.meterTrip(tripId, lat, lng);
      }
    }
  }

  /**
   * Drop the next stop from the leg's waypoints once the car reaches it, so
   * later re-routes (and the stops still shown as ahead) skip it. Mutates
   * [nav] to match what it stores.
   */
  private async passReachedStop(tripId: string, pos: LatLng, nav: NavContext) {
    const next = nav.waypoints?.[0];
    if (!next || haversineMeters(pos, next) > STOP_REACHED_M) return;
    nav.waypoints = (nav.waypoints ?? []).slice(1);
    await this.redis.client.hset(
      RedisKeys.tripNav(tripId),
      'waypoints',
      JSON.stringify(nav.waypoints),
    );
  }

  /** Load the leg's navigation context; null when none is stored. */
  private async readNav(tripId: string): Promise<NavContext | null> {
    const h = await this.redis.client.hgetall(RedisKeys.tripNav(tripId));
    if (!h || !h.targetLat || !h.targetLng) return null;
    const lat = Number(h.targetLat);
    const lng = Number(h.targetLng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
    const speed = Number(h.avgSpeedMps);
    let waypoints: LatLng[] = [];
    try {
      const parsed = JSON.parse(h.waypoints ?? '[]');
      if (Array.isArray(parsed)) {
        waypoints = parsed.filter(
          (p) => Number.isFinite(p?.lat) && Number.isFinite(p?.lng),
        );
      }
    } catch {
      waypoints = [];
    }
    return {
      phase: h.phase === 'trip' ? 'trip' : 'approach',
      target: { lat, lng },
      polyline: h.polyline ?? '',
      waypoints,
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
   * Deviation + stopped watchdogs for one GPS fix. Reads the per-trip watch
   * hash once, decides, and writes back in a single pipeline.
   */
  private async watch(
    tripId: string,
    riderId: string,
    pos: LatLng,
    nav: NavContext | null,
    now: number,
  ): Promise<void> {
    const key = RedisKeys.tripWatch(tripId);
    const w = (await this.redis.client.hgetall(key)) ?? {};
    const pipe = this.redis.client.pipeline();
    await this.watchRoute(tripId, riderId, pos, nav, now, w, pipe);
    this.watchStopped(tripId, riderId, pos, nav, now, w, pipe);
    pipe.expire(key, WATCH_TTL_S);
    await pipe.exec();
  }

  /**
   * Has the driver left the route the rider is watching? Only checked on the
   * on-trip leg: the approach polyline is a single suggestion computed at
   * assignment, and drivers legitimately take another road to the pickup, so
   * policing it would alert on nearly every ride. Once a deviation is
   * confirmed the route is recomputed from where the driver actually is, so
   * the rider's map follows the road being driven instead of a line the car
   * left minutes ago.
   */
  private async watchRoute(
    tripId: string,
    riderId: string,
    pos: LatLng,
    nav: NavContext | null,
    now: number,
    w: Record<string, string>,
    pipe: ReturnType<RedisService['client']['pipeline']>,
  ): Promise<void> {
    const key = RedisKeys.tripWatch(tripId);
    if (!nav || nav.phase !== 'trip' || !nav.polyline) return;
    let projection: ReturnType<typeof projectOntoPolyline>;
    try {
      projection = projectOntoPolyline(pos, decodePolyline(nav.polyline));
    } catch {
      return;
    }
    if (!projection) return;
    const { offsetM } = projection;

    if (offsetM <= OFF_ROUTE_CLEAR_M) {
      // Back on the route. Re-arm so a later wrong turn alerts again, and tell
      // the rider so the app can drop the banner it raised.
      if (w.offRouteAlerted === '1') {
        this.realtime.emitToUser(riderId, 'trip:back_on_route', { tripId });
      }
      if (w.offRouteStreak || w.offRouteAlerted) {
        pipe.hdel(key, 'offRouteStreak', 'offRouteAlerted');
      }
      return;
    }
    // Between the two thresholds: neither a deviation nor a return. Hold.
    if (offsetM < OFF_ROUTE_M) return;

    const streak = Number(w.offRouteStreak ?? 0) + 1;
    pipe.hset(key, 'offRouteStreak', String(streak));
    if (streak < OFF_ROUTE_PINGS || w.offRouteAlerted === '1') return;

    // Claim the alert atomically: with several fixes in flight only one wins.
    const claimed = await this.redis.client.hsetnx(key, 'offRouteAlerted', '1');
    if (claimed !== 1) return;

    this.realtime.emitToUser(riderId, 'trip:off_route', {
      tripId,
      offsetM,
      lat: pos.lat,
      lng: pos.lng,
    });
    void this.notifications
      .notifyTrip(riderId, 'off_route', { tripId })
      .catch(() => undefined);
    await this.reroute(tripId, riderId, pos, nav, now, w);
  }

  /**
   * Recompute the live route from the driver's actual position to the leg's
   * target and push it to the rider, so the drawn line follows the road taken.
   * Rate-limited and entirely best-effort — a routing failure leaves the old
   * line in place, which is what the rider saw a moment ago anyway.
   */
  private async reroute(
    tripId: string,
    riderId: string,
    pos: LatLng,
    nav: NavContext,
    now: number,
    w: Record<string, string>,
  ): Promise<void> {
    const last = Number(w.rerouteTs ?? 0);
    if (Number.isFinite(last) && now - last < REROUTE_MIN_GAP_S * 1000) return;
    try {
      // Through the stops still ahead — routing straight to the destination
      // erased them from the rider's map at the first re-route.
      const route = await routeThrough(this.geo, [pos, ...(nav.waypoints ?? []), nav.target]);
      if (!route?.polyline) return;
      await this.redis.client.hset(RedisKeys.tripNav(tripId), {
        polyline: route.polyline,
        avgSpeedMps:
          route.durationS > 0 ? route.distanceM / route.durationS : '',
      });
      await this.redis.client.hset(
        RedisKeys.tripWatch(tripId),
        'rerouteTs',
        String(now),
      );
      this.realtime.emitToUser(riderId, 'trip:route_updated', {
        tripId,
        phase: nav.phase,
        polyline: route.polyline,
        distanceM: route.distanceM,
        durationS: route.durationS,
      });
    } catch (e) {
      this.logger.warn(`reroute failed for trip ${tripId}: ${String(e)}`);
    }
  }

  /**
   * Has the driver stopped? Anchored on the last point they were meaningfully
   * away from: while they keep moving the anchor follows them and the clock
   * keeps resetting, so only a genuine standstill accumulates time.
   */
  private watchStopped(
    tripId: string,
    riderId: string,
    pos: LatLng,
    nav: NavContext | null,
    now: number,
    w: Record<string, string>,
    pipe: ReturnType<RedisService['client']['pipeline']>,
  ): void {
    const key = RedisKeys.tripWatch(tripId);
    const anchorLat = Number(w.moveLat);
    const anchorLng = Number(w.moveLng);
    const since = Number(w.moveTs);
    const anchored =
      Number.isFinite(anchorLat) &&
      Number.isFinite(anchorLng) &&
      Number.isFinite(since) &&
      w.moveTs !== undefined;
    if (!anchored) {
      pipe.hset(key, {
        moveLat: String(pos.lat),
        moveLng: String(pos.lng),
        moveTs: String(now),
      });
      return;
    }

    const moved = haversineMeters({ lat: anchorLat, lng: anchorLng }, pos);
    if (moved > STOPPED_RADIUS_M) {
      // Moving again: re-anchor and re-arm.
      pipe.hset(key, {
        moveLat: String(pos.lat),
        moveLng: String(pos.lng),
        moveTs: String(now),
      });
      if (w.stoppedAlerted === '1') {
        pipe.hdel(key, 'stoppedAlerted');
        this.realtime.emitToUser(riderId, 'trip:driver_moving', { tripId });
      }
      return;
    }
    if (w.stoppedAlerted === '1') return; // already told them about this stop
    const stoppedMs = now - since;
    if (stoppedMs < STOPPED_AFTER_S * 1000) return;

    // Claim outside the pipeline so only one concurrent ping emits.
    void this.redis.client
      .hsetnx(key, 'stoppedAlerted', '1')
      .then((claimed) => {
        if (claimed !== 1) return;
        this.realtime.emitToUser(riderId, 'trip:driver_stopped', {
          tripId,
          stoppedSec: Math.round(stoppedMs / 1000),
          phase: nav?.phase ?? null,
          lat: pos.lat,
          lng: pos.lng,
        });
        void this.notifications
          .notifyTrip(riderId, 'driver_stopped', { tripId })
          .catch(() => undefined);
      })
      .catch(() => undefined);
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
