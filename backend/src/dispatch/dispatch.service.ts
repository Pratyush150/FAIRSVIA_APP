import { Injectable, Logger, Inject } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { Trip, TripStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { RealtimeService } from '../realtime/realtime.service';
import { NotificationsService } from '../notifications/notifications.service';
import { TripStateMachine } from '../trips/trip-state-machine';
import { FavoritesService } from '../favorites/favorites.service';
import { GEO_PROVIDER, GeoProvider } from '../geo/geo-provider.interface';
import {
  QUEUE_DISPATCH,
  DISPATCH_JOB,
  DEFAULT_JOB_OPTS,
} from '../common/queue/queue.constants';

// How long a driver has to respond to an offer before we move on. A driver who
// *ghosts* (neither accepts nor declines) blocks this rider's sequential offer
// loop for the whole window, so it directly bounds the worst-case match-latency
// tail. 10s is still an easy human-tap window while keeping ghost recovery snappy.
// How long a driver has to accept an offer. Configurable so demos/recordings
// can give a human time to switch apps; production keeps the snappy 10s.
const OFFER_TTL_MS = Number(process.env.OFFER_TTL_MS ?? 10000);
// Poll the response key fairly tightly: a driver auto-accepts in well under a
// second, so this mostly sets the floor on match latency. Cheap Redis GETs.
const RESPONSE_POLL_MS = 100;
const START_RADIUS_KM = 3;
const MAX_RADIUS_KM = 9;
const RADIUS_STEP_KM = 2;
// A driver whose app crashes / loses network without going offline never emits
// `status:offline`, so their GEO-set entry lingers with a stale position and
// dispatch keeps offering to a ghost (burned offer-TTLs, spurious no_drivers).
// Online drivers stream GPS every few seconds, so a candidate with no ping in
// this window is treated as gone and evicted from the pool. Self-healing: a
// driver that reconnects is re-added on their next ping.
const PRESENCE_STALE_MS = Number(process.env.PRESENCE_STALE_MS ?? 45000);
// When a full expanding-ring sweep finds no *available* driver (every nearby
// driver is busy on another trip), don't give up immediately — under bursty
// demand near capacity a driver frees up within seconds. Keep the trip in
// MATCHING (rider still sees "finding driver") and re-sweep, up to a bounded
// total window. Only after the window elapses do we declare no_drivers. This
// turns momentary supply exhaustion from a hard failure into a short wait.
const MATCH_WINDOW_MS = 45000;
const RESWEEP_DELAY_MS = 2500;

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
    private readonly favorites: FavoritesService,
    @Inject(GEO_PROVIDER) private readonly geo: GeoProvider,
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

    // The rider's favourite drivers jump the queue when they're nearby.
    const favorites = await this.favorites
      .favoriteDriverIds(trip.riderId)
      .catch(() => new Set<string>());

    // Re-sweep until a driver is assigned or the matching window elapses. Each
    // sweep re-reads the live GEO set, so drivers that were busy last pass are
    // reconsidered as they free up.
    const deadline = Date.now() + MATCH_WINDOW_MS;
    for (;;) {
      const outcome = await this.sweep(trip, favorites, deadline);
      if (outcome !== 'exhausted') return; // 'assigned' or 'cancelled'
      if (Date.now() >= deadline) break;
      await this.sleep(RESWEEP_DELAY_MS);
      // Bail out if the trip left MATCHING (cancelled) during the wait.
      const cur = await this.prisma.trip.findUnique({
        where: { id: tripId },
        select: { status: true },
      });
      if (cur?.status !== TripStatus.matching) return;
    }

    // Window elapsed with no available driver.
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

  /**
   * One expanding-ring pass: offer to nearby available drivers, nearest first,
   * favourites jumping the queue. Returns:
   *   - 'assigned'  a driver accepted (trip is now ACCEPTED)
   *   - 'cancelled' the trip left MATCHING mid-sweep
   *   - 'exhausted' no available driver responded across the whole ring
   * `tried` is per-sweep so a driver busy this pass is reconsidered next pass.
   */
  private async sweep(
    trip: Trip,
    favorites: Set<string>,
    deadline: number,
  ): Promise<'assigned' | 'cancelled' | 'exhausted'> {
    const tried = new Set<string>();
    for (
      let radiusKm = START_RADIUS_KM;
      radiusKm <= MAX_RADIUS_KM;
      radiusKm += RADIUS_STEP_KM
    ) {
      const candidates = this.favoritesFirst(
        await this.nearestDrivers(trip, radiusKm),
        favorites,
      );
      for (const driverId of candidates) {
        // Enforce the match window BETWEEN OFFERS, not just between sweeps: each
        // ghosted offer burns a full OFFER_TTL, so a ring full of unresponsive
        // drivers could otherwise run minutes past the deadline before the rider
        // is told no_drivers. Bail as soon as the window is spent.
        if (Date.now() >= deadline) return 'exhausted';
        if (tried.has(driverId)) continue;
        tried.add(driverId);

        // Skip if the trip was cancelled while we were offering.
        const current = await this.prisma.trip.findUnique({
          where: { id: trip.id },
          select: { status: true },
        });
        if (current?.status !== TripStatus.matching) return 'cancelled';

        if ((await this.redis.client.get(RedisKeys.driverStatus(driverId))) !== 'online') {
          continue;
        }
        if (await this.offerTo(driverId, trip)) return 'assigned';
      }
    }
    return 'exhausted';
  }

  /**
   * Stable-partition the distance-sorted candidates so the rider's favourites
   * come first, each group still in nearest-first order.
   */
  private favoritesFirst(
    candidates: string[],
    favorites: Set<string>,
  ): string[] {
    if (favorites.size === 0) return candidates;
    const fav: string[] = [];
    const rest: string[] = [];
    for (const id of candidates) {
      (favorites.has(id) ? fav : rest).push(id);
    }
    return [...fav, ...rest];
  }

  private async nearestDrivers(trip: Trip, radiusKm: number): Promise<string[]> {
    const result = (await this.redis.client.geosearch(
      RedisKeys.driversGeo(trip.tier),
      'FROMLONLAT',
      trip.pickupLng,
      trip.pickupLat,
      'BYRADIUS',
      radiusKm,
      'km',
      'ASC',
    )) as string[];
    if (result.length === 0) return result;
    return this.evictStale(trip.tier, result);
  }

  /**
   * Drops ghost drivers — those whose last GPS ping is older than
   * PRESENCE_STALE_MS — from the candidate list AND from the GEO pool, so we
   * never offer a trip to a driver who has silently disappeared. Reads all
   * timestamps in one pipeline to keep the hot path cheap.
   */
  private async evictStale(tier: string, ids: string[]): Promise<string[]> {
    const pipeline = this.redis.client.pipeline();
    for (const id of ids) pipeline.hget(RedisKeys.driverLoc(id), 'ts');
    const res = await pipeline.exec();
    const now = Date.now();
    const fresh: string[] = [];
    const stale: string[] = [];
    ids.forEach((id, i) => {
      const ts = res?.[i]?.[1] as string | null;
      if (ts && now - Number(ts) <= PRESENCE_STALE_MS) {
        fresh.push(id);
      } else {
        stale.push(id);
      }
    });
    if (stale.length > 0) {
      await this.redis.client.zrem(RedisKeys.driversGeo(tier), ...stale);
    }
    return fresh;
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

    // Route from the driver's current position TO the pickup, so the rider's map
    // can draw the approach leg (driver → you) while the driver is en route,
    // instead of the trip route. Best-effort: if the driver's position is
    // unknown or routing fails, omit it and the client falls back to the trip
    // route. Provider-agnostic — uses whatever GeoProvider is configured.
    const driverPolyline = await this.approachPolyline(driverId, trip);

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
      driverPolyline,
    });
    // The driver needs the same geometry the rider gets: the approach leg
    // (their car → the pickup) so their map can show exactly where they're
    // collecting the rider from, plus the trip route for the on-trip leg.
    this.realtime.emitToUser(driverId, 'trip:assigned', {
      tripId: trip.id,
      polyline: trip.routePolyline,
      driverPolyline,
    });
    void this.notifications.notifyTrip(trip.riderId, 'accepted', {
      tripId: trip.id,
    });
    this.logger.log(`Trip ${trip.id} assigned to driver ${driverId}`);
    return true;
  }

  /**
   * Best-effort encoded polyline from the driver's last-known position to the
   * trip pickup. Returns undefined if the position is unknown or routing fails.
   */
  private async approachPolyline(
    driverId: string,
    trip: Trip,
  ): Promise<string | undefined> {
    try {
      const [lat, lng] = await this.redis.client.hmget(
        RedisKeys.driverLoc(driverId),
        'lat',
        'lng',
      );
      const dlat = lat != null ? Number(lat) : NaN;
      const dlng = lng != null ? Number(lng) : NaN;
      if (!Number.isFinite(dlat) || !Number.isFinite(dlng)) return undefined;
      const approach = await this.geo.route(
        { lat: dlat, lng: dlng },
        { lat: trip.pickupLat, lng: trip.pickupLng },
      );
      return approach.polyline || undefined;
    } catch {
      return undefined;
    }
  }
}
