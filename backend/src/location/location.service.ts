import { Injectable } from '@nestjs/common';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { RealtimeService } from '../realtime/realtime.service';

/** A single GPS segment longer than this (meters) is treated as a fix jump /
 *  reconnect gap and skipped, so the odometer isn't inflated by teleports. */
const MAX_SANE_SEGMENT_M = 2000;

/**
 * Atomic trip odometer step, run inside Redis so read-add-write can't interleave
 * across concurrent pings (Socket.IO doesn't serialize async handlers).
 *   KEYS[1] = trip driven-meters counter (exists only while in_progress)
 *   KEYS[2] = trip last-metered-point hash
 *   ARGV = lat, lng, maxSegmentMeters
 * No-ops unless metering is active (the counter was seeded at trip start).
 */
const METER_STEP_LUA = `
if redis.call('EXISTS', KEYS[1]) == 0 then return false end
local last = redis.call('HMGET', KEYS[2], 'lat', 'lng')
local lat2 = tonumber(ARGV[1])
local lng2 = tonumber(ARGV[2])
local maxseg = tonumber(ARGV[3])
if last[1] and last[2] then
  local rad = math.pi / 180
  local lat1 = tonumber(last[1]) * rad
  local la2 = lat2 * rad
  local dLat = (lat2 - tonumber(last[1])) * rad
  local dLng = (lng2 - tonumber(last[2])) * rad
  local a = math.sin(dLat / 2) ^ 2 + math.cos(lat1) * math.cos(la2) * math.sin(dLng / 2) ^ 2
  local seg = 2 * 6371000 * math.asin(math.sqrt(a))
  if seg > 0 and seg < maxseg then
    redis.call('INCRBYFLOAT', KEYS[1], seg)
  end
end
redis.call('HSET', KEYS[2], 'lat', lat2, 'lng', lng2)
return redis.call('GET', KEYS[1])
`;

export interface LocationPing {
  lat: number;
  lng: number;
  heading?: number;
  speed?: number;
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
    const { lat, lng, heading = 0, speed = 0 } = ping;

    await this.redis.client.hset(RedisKeys.driverLoc(driverId), {
      lat,
      lng,
      heading,
      speed,
      ts: Date.now(),
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

    // On a trip → stream the position to the rider watching the map.
    if (tripId) {
      const riderId = await this.redis.client.get(RedisKeys.driverActiveRider(driverId));
      if (riderId) {
        this.realtime.emitToUser(riderId, 'trip:driver_location', {
          tripId,
          lat,
          lng,
          heading,
        });
      }
      await this.meterTrip(tripId, lat, lng);
    }
  }

  /**
   * Accumulates the actually-driven distance while a trip is in progress. The
   * odometer key (`trip:{id}:driven`) exists only between start and complete —
   * so pings during en-route-to-pickup are ignored. Used to recompute the
   * final fare from real distance rather than the up-front estimate.
   */
  private async meterTrip(tripId: string, lat: number, lng: number): Promise<void> {
    // One atomic EVAL: gates on active metering, accumulates the segment, and
    // advances the last point — immune to interleaving across burst pings.
    await this.redis.client.eval(
      METER_STEP_LUA,
      2,
      RedisKeys.tripDriven(tripId),
      RedisKeys.tripMeterLast(tripId),
      lat,
      lng,
      MAX_SANE_SEGMENT_M,
    );
  }
}
