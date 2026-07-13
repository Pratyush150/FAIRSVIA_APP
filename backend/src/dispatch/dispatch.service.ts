import { Injectable, Logger } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { Trip, TripStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { RealtimeService } from '../realtime/realtime.service';
import { NotificationsService } from '../notifications/notifications.service';
import { TripStateMachine } from '../trips/trip-state-machine';
import {
  QUEUE_DISPATCH,
  DISPATCH_JOB,
  DEFAULT_JOB_OPTS,
} from '../common/queue/queue.constants';

const OFFER_TTL_MS = 15000;
// Poll the response key fairly tightly: a driver auto-accepts in well under a
// second, so this mostly sets the floor on match latency. Cheap Redis GETs.
const RESPONSE_POLL_MS = 100;
const START_RADIUS_KM = 3;
const MAX_RADIUS_KM = 9;
const RADIUS_STEP_KM = 2;

/**
 * The DISCO equivalent: matches a requested trip to the nearest available
 * driver via a sequential offer loop with per-driver locks and offer TTLs.
 *
 * The loop runs inside a BullMQ job (see DispatchProcessor), so if the backend
 * dies mid-match the job is retried/resumed instead of the trip being stranded
 * in `matching`. Driver accept/decline is signalled through Redis, so it works
 * no matter which node (or process) holds the offer.
 */
@Injectable()
export class DispatchService {
  private readonly logger = new Logger('Dispatch');

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly realtime: RealtimeService,
    private readonly notifications: NotificationsService,
    private readonly stateMachine: TripStateMachine,
    @InjectQueue(QUEUE_DISPATCH) private readonly queue: Queue,
  ) {}

  /**
   * Enqueue matching for a freshly-created trip. Durable: the job survives a
   * restart. `jobId: tripId` de-dupes so a trip is only ever matched once at a
   * time.
   */
  async dispatchTrip(tripId: string): Promise<void> {
    await this.queue.add(
      DISPATCH_JOB,
      { tripId },
      { ...DEFAULT_JOB_OPTS, jobId: tripId },
    );
  }

  /**
   * The actual offer loop — invoked by the queue worker. Idempotent/resumable:
   * a fresh trip is moved REQUESTED→MATCHING; a trip already in MATCHING (e.g.
   * a retried job) simply resumes offering; anything else is a no-op.
   */
  async runDispatch(tripId: string): Promise<void> {
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) return;

    if (trip.status === TripStatus.requested) {
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
    } else if (trip.status !== TripStatus.matching) {
      return; // already assigned, cancelled, or terminal
    }

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
    const lockKey = RedisKeys.driverOfferLock(driverId);
    const locked = await this.redis.client.set(lockKey, trip.id, 'PX', 20000, 'NX');
    if (locked !== 'OK') return false;

    try {
      // Record the live offer and clear any stale response for this trip.
      await this.redis.client.set(
        RedisKeys.dispatchOffer(trip.id),
        driverId,
        'PX',
        OFFER_TTL_MS,
      );
      await this.redis.client.del(RedisKeys.dispatchResponse(trip.id));

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

      const accepted = await this.awaitResponse(trip.id, driverId);
      await this.redis.client.del(RedisKeys.dispatchOffer(trip.id));

      if (!accepted) {
        this.realtime.emitToUser(driverId, 'trip:offer_expired', { tripId: trip.id });
        return false;
      }
      return await this.assign(trip, driverId);
    } finally {
      await this.redis.client.del(lockKey);
    }
  }

  /**
   * Wait for the offered driver's response by polling the Redis response key.
   * Cross-process: the accept/decline may be handled by another node — it lands
   * in Redis and we pick it up here. Resolves false on TTL timeout.
   */
  private async awaitResponse(tripId: string, driverId: string): Promise<boolean> {
    const respKey = RedisKeys.dispatchResponse(tripId);
    const deadline = Date.now() + OFFER_TTL_MS;
    while (Date.now() < deadline) {
      const raw = await this.redis.client.get(respKey);
      if (raw !== null) {
        await this.redis.client.del(respKey);
        // Format "accepted:driverId" — ignore a response from a stale driver.
        const [verdict, who] = raw.split(':');
        if (who === driverId) return verdict === '1';
      }
      await this.sleep(RESPONSE_POLL_MS);
    }
    return false;
  }

  /**
   * Called by the gateway/REST when a driver accepts or declines. Returns true
   * only if there is a live offer to *this* driver for *this* trip (so the REST
   * endpoint can 400 on an expired/foreign offer). Cross-process safe.
   */
  async respondToOffer(
    driverId: string,
    tripId: string,
    accepted: boolean,
  ): Promise<boolean> {
    const offeree = await this.redis.client.get(RedisKeys.dispatchOffer(tripId));
    if (offeree !== driverId) return false;
    await this.redis.client.set(
      RedisKeys.dispatchResponse(tripId),
      `${accepted ? '1' : '0'}:${driverId}`,
      'PX',
      30000,
    );
    return true;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
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
