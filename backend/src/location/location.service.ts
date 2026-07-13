import { Injectable } from '@nestjs/common';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { RealtimeService } from '../realtime/realtime.service';

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

    const status = await this.redis.client.get(RedisKeys.driverStatus(driverId));
    if (status === 'online') {
      const tier = await this.redis.client.get(RedisKeys.driverTier(driverId));
      if (tier) {
        // ioredis geoadd: key, longitude, latitude, member
        await this.redis.client.geoadd(RedisKeys.driversGeo(tier), lng, lat, driverId);
      }
    }

    // On a trip → stream the position to the rider watching the map.
    const [riderId, tripId] = await Promise.all([
      this.redis.client.get(RedisKeys.driverActiveRider(driverId)),
      this.redis.client.get(RedisKeys.driverActiveTrip(driverId)),
    ]);
    if (riderId && tripId) {
      this.realtime.emitToUser(riderId, 'trip:driver_location', {
        tripId,
        lat,
        lng,
        heading,
      });
    }
  }
}
