import { Injectable, Logger } from '@nestjs/common';
import { Trip, TripStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { RealtimeService } from '../realtime/realtime.service';
import { NotificationsService } from '../notifications/notifications.service';
import { TripStateMachine } from '../trips/trip-state-machine';

const OFFER_TTL_MS = 15000;
const START_RADIUS_KM = 3;
const MAX_RADIUS_KM = 9;
const RADIUS_STEP_KM = 2;

/**
 * The DISCO equivalent: matches a requested trip to the nearest available
 * driver via a sequential offer loop with per-driver locks and offer TTLs.
 * Single-node in-memory pending offers (multi-node would coordinate via Redis).
 */
@Injectable()
export class DispatchService {
  private readonly logger = new Logger('Dispatch');
  private readonly pendingOffers = new Map<string, (accepted: boolean) => void>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly realtime: RealtimeService,
    private readonly notifications: NotificationsService,
    private readonly stateMachine: TripStateMachine,
  ) {}

  /** Kick off matching for a freshly-created trip (fire-and-forget). */
  async dispatchTrip(tripId: string): Promise<void> {
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip || trip.status !== TripStatus.requested) return;

    try {
      await this.stateMachine.transition({
        tripId,
        from: TripStatus.requested,
        to: TripStatus.matching,
        actor: 'system',
      });
    } catch {
      return; // cancelled before matching started
    }
    this.realtime.emitToUser(trip.riderId, 'trip:matching', { tripId });

    const tried = new Set<string>();
    for (
      let radiusKm = START_RADIUS_KM;
      radiusKm <= MAX_RADIUS_KM;
      radiusKm += RADIUS_STEP_KM
    ) {
      const candidates = await this.nearestDrivers(trip, radiusKm);
      for (const driverId of candidates) {
        if (tried.has(driverId)) continue;
        tried.add(driverId);

        // Skip if the trip was cancelled while we were offering.
        const current = await this.prisma.trip.findUnique({
          where: { id: tripId },
          select: { status: true },
        });
        if (current?.status !== TripStatus.matching) return;

        if ((await this.redis.client.get(RedisKeys.driverStatus(driverId))) !== 'online') {
          continue;
        }
        if (await this.offerTo(driverId, trip)) return; // assigned
      }
    }

    // Exhausted the search.
    try {
      await this.stateMachine.transition({
        tripId,
        from: TripStatus.matching,
        to: TripStatus.no_drivers,
        actor: 'system',
      });
      this.realtime.emitToUser(trip.riderId, 'trip:no_drivers', { tripId });
      void this.notifications.notifyTrip(trip.riderId, 'no_drivers', { tripId });
    } catch {
      // Trip left MATCHING (cancelled) — nothing to do.
    }
  }

  private async nearestDrivers(trip: Trip, radiusKm: number): Promise<string[]> {
    const result = await this.redis.client.geosearch(
      RedisKeys.driversGeo(trip.tier),
      'FROMLONLAT',
      trip.pickupLng,
      trip.pickupLat,
      'BYRADIUS',
      radiusKm,
      'km',
      'ASC',
    );
    return result as string[];
  }

  /** Offer to one driver under a lock; resolve when they accept/decline/expire. */
  private async offerTo(driverId: string, trip: Trip): Promise<boolean> {
    const lockKey = `driver:${driverId}:offerlock`;
    const locked = await this.redis.client.set(lockKey, trip.id, 'PX', 20000, 'NX');
    if (locked !== 'OK') return false;

    try {
      this.realtime.emitToUser(driverId, 'trip:offer', {
        tripId: trip.id,
        pickup: { lat: trip.pickupLat, lng: trip.pickupLng, address: trip.pickupAddr },
        dropoff: { lat: trip.dropoffLat, lng: trip.dropoffLng, address: trip.dropoffAddr },
        fare: Number(trip.fareEstimate ?? 0),
        tier: trip.tier,
        distanceM: trip.distanceM,
        durationS: trip.durationS,
        expiresInSec: OFFER_TTL_MS / 1000,
      });

      const accepted = await this.waitForResponse(trip.id, driverId);
      if (!accepted) {
        this.realtime.emitToUser(driverId, 'trip:offer_expired', { tripId: trip.id });
        return false;
      }
      return await this.assign(trip, driverId);
    } finally {
      await this.redis.client.del(lockKey);
    }
  }

  private waitForResponse(tripId: string, driverId: string): Promise<boolean> {
    const key = `${tripId}:${driverId}`;
    return new Promise<boolean>((resolve) => {
      const timer = setTimeout(() => {
        this.pendingOffers.delete(key);
        resolve(false);
      }, OFFER_TTL_MS);
      this.pendingOffers.set(key, (accepted) => {
        clearTimeout(timer);
        this.pendingOffers.delete(key);
        resolve(accepted);
      });
    });
  }

  /** Called by the gateway/REST when a driver accepts or declines an offer. */
  respondToOffer(driverId: string, tripId: string, accepted: boolean): boolean {
    const key = `${tripId}:${driverId}`;
    const resolver = this.pendingOffers.get(key);
    if (!resolver) return false;
    resolver(accepted);
    return true;
  }

  private async assign(trip: Trip, driverId: string): Promise<boolean> {
    try {
      await this.stateMachine.transition({
        tripId: trip.id,
        from: TripStatus.matching,
        to: TripStatus.accepted,
        actor: 'driver',
        data: { driverId, acceptedAt: new Date() },
        meta: { driverId },
      });
    } catch {
      return false; // trip no longer matching (cancelled/other)
    }

    // Take the driver out of the pool and mark them on-trip.
    await this.redis.client.zrem(RedisKeys.driversGeo(trip.tier), driverId);
    await this.redis.client.set(RedisKeys.driverStatus(driverId), 'on_trip');
    await this.redis.client.set(RedisKeys.driverActiveTrip(driverId), trip.id);
    await this.redis.client.set(RedisKeys.driverActiveRider(driverId), trip.riderId);

    const driver = await this.prisma.user.findUnique({
      where: { id: driverId },
      include: { driverProfile: true },
    });

    this.realtime.emitToUser(trip.riderId, 'trip:accepted', {
      tripId: trip.id,
      driver: {
        id: driverId,
        name: driver?.fullName ?? 'Your driver',
        rating: Number(driver?.ratingAvg ?? 5),
      },
      vehicle: {
        make: driver?.driverProfile?.vehicleMake,
        model: driver?.driverProfile?.vehicleModel,
        color: driver?.driverProfile?.vehicleColor,
        plate: driver?.driverProfile?.plateNumber,
      },
      polyline: trip.routePolyline,
    });
    this.realtime.emitToUser(driverId, 'trip:assigned', { tripId: trip.id });
    void this.notifications.notifyTrip(trip.riderId, 'accepted', {
      tripId: trip.id,
    });
    this.logger.log(`Trip ${trip.id} assigned to driver ${driverId}`);
    return true;
  }
}
