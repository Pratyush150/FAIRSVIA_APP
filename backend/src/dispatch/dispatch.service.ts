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
import { DriversService } from '../drivers/drivers.service';
import { SurgeService } from '../surge/surge.service';
import { OpsFlagsService } from '../ops/ops-flags.service';
import { MetricsService } from '../common/metrics/metrics.service';
import { GEO_PROVIDER, GeoProvider, RouteResult } from '../geo/geo-provider.interface';
import {
  SMS_PROVIDER,
  SmsProvider,
} from '../auth/sms/sms-provider.interface';
import { haversineMeters } from '../geo/geo.util';
import {
  QUEUE_DISPATCH,
  DISPATCH_JOB,
  DEFAULT_JOB_OPTS,
} from '../common/queue/queue.constants';

// How long a driver has to respond to an offer before we move on. A driver who
// *ghosts* (neither accepts nor declines) blocks this rider's sequential offer
// loop for the whole window, so it directly bounds the worst-case match-latency
// tail: every unresponsive driver in the ring costs the waiting rider a full
// window. 15s matches what the big networks give a driver — comfortably enough
// to glance at the card and tap, without stranding the rider behind someone who
// put their phone down.
//
// It stays configurable for demos, but is CLAMPED: a stray `OFFER_TTL_MS=90000`
// left in a deployed .env is how field testing ended up with a 90-second
// countdown on the driver's phone, and (before the lock TTL was derived from
// it) how the same driver could be offered two trips at once.
const OFFER_TTL_MIN_MS = 5000;
const OFFER_TTL_MAX_MS = 30000;
export const OFFER_TTL_MS = clampOfferTtl(Number(process.env.OFFER_TTL_MS ?? 15000));

export function clampOfferTtl(ms: number): number {
  if (!Number.isFinite(ms) || ms <= 0) return 15000;
  return Math.min(OFFER_TTL_MAX_MS, Math.max(OFFER_TTL_MIN_MS, ms));
}
// The per-driver offer lock MUST outlive the offer window, or a second dispatch
// could lock the same driver mid-offer and double-assign them (both trips accept).
// Hold the lock a fixed buffer beyond however long the driver has to respond.
const OFFER_LOCK_TTL_MS = OFFER_TTL_MS + 10000;
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
// ~90s: a rider keeps "finding driver" this long, and — critically — a driver
// who comes online within this window of a booking still gets offered the
// waiting ride (each re-sweep re-reads the live pool, so a freshly-online driver
// in the pickup's region is picked up on the next pass).
const MATCH_WINDOW_MS = 90000;
const RESWEEP_DELAY_MS = 2500;
// Cap how many of the closest candidates get a road-ETA refinement, to bound the
// routing calls added to the hot matching path.
const ETA_RANK_LIMIT = 5;
// Fallback approach speed (m/s) for an ETA when no road route was computed for
// a candidate — straight-line distance at ~city pace. Only ever a rough hint.
const FALLBACK_APPROACH_MPS = 8;
// How long the per-trip "declined" set lives: longer than any matching window.
const DECLINED_TTL_S = 600;

/** Approach routes computed while ranking, reused for the offer card. */
type ApproachCache = Map<string, RouteResult | undefined>;

/** Rider identity shown on the driver's offer card. */
interface RiderInfo {
  name: string;
  rating: number;
}

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
    @Inject(SMS_PROVIDER) private readonly sms: SmsProvider,
    @InjectQueue(QUEUE_DISPATCH) private readonly queue: Queue,
    private readonly drivers: DriversService,
    private readonly surge: SurgeService,
    private readonly flags: OpsFlagsService,
    private readonly metrics: MetricsService,
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
   * Re-dispatch everything parked while matching was paused, and report how
   * many were released. Called when the `dispatchPaused` switch goes off.
   *
   * Trips that have since ended (cancelled, expired) are dropped from the set
   * rather than re-offered — `runDispatch` would no-op on them anyway, but
   * leaving them there makes the "waiting" count lie.
   */
  async resumeDeferred(): Promise<number> {
    const key = RedisKeys.dispatchDeferred();
    const ids = await this.redis.client.smembers(key);
    if (ids.length === 0) return 0;
    await this.redis.client.del(key);

    let released = 0;
    for (const tripId of ids) {
      const trip = await this.prisma.trip.findUnique({
        where: { id: tripId },
        select: { status: true },
      });
      if (trip?.status !== TripStatus.requested) continue;
      // Drop the retained completed job first. `dispatchTrip` de-dupes on
      // `jobId: tripId`, and BullMQ keeps completed jobs for an hour
      // (removeOnComplete.age) — so without this the re-add is silently
      // discarded as a duplicate and the trip stays parked for ever while the
      // log cheerfully reports it was released.
      await this.queue.remove(tripId).catch(() => undefined);
      await this.dispatchTrip(tripId);
      released += 1;
    }
    this.logger.warn(`dispatch resumed — re-dispatched ${released} trip(s)`);
    return released;
  }

  /** How many trips are currently parked behind the pause. */
  deferredCount(): Promise<number> {
    return this.redis.client.scard(RedisKeys.dispatchDeferred());
  }

  /**
   * The actual offer loop — invoked by the queue worker. Idempotent/resumable:
   * a fresh trip is moved REQUESTED→MATCHING; a trip already in MATCHING (e.g.
   * a retried job) simply resumes offering; anything else is a no-op.
   */
  async runDispatch(tripId: string): Promise<void> {
    // Kill switch: stop matching new trips.
    //
    // Park the trip in a deferred set and return cleanly. Throwing here (the
    // obvious implementation) looks like it defers the work but does not: the
    // job has `attempts: 3` with a 2s backoff, so any pause longer than about
    // six seconds exhausts the retries and strands the rider in `requested`
    // for ever. A pause that quietly loses trips is worse than no pause.
    //
    // The trip's status is left untouched, so nothing observable changes for
    // the rider beyond waiting — and `resumeDeferred()` picks it up the moment
    // the switch goes off.
    if (await this.flags.isOn('dispatchPaused')) {
      await this.redis.client.sadd(RedisKeys.dispatchDeferred(), tripId);
      this.logger.warn(`dispatch paused — deferred trip ${tripId}`);
      return;
    }
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

    // Rider identity for the driver's offer card — fetched once per dispatch
    // (not per offer). Best-effort: a neutral label if the lookup fails.
    // Wrapped so a failure (sync or async) can never break matching — the offer
    // just falls back to a neutral rider label.
    const rider = await Promise.resolve()
      .then(() =>
        this.prisma.user.findUnique({
          where: { id: trip.riderId },
          select: { fullName: true, ratingAvg: true },
        }),
      )
      .catch(() => null);
    const riderInfo: RiderInfo = {
      name: rider?.fullName ?? 'Rider',
      rating: Number(rider?.ratingAvg ?? 5),
    };

    // Re-sweep until a driver is assigned or the matching window elapses. Each
    // sweep re-reads the live GEO set, so drivers that were busy last pass are
    // reconsidered as they free up.
    const deadline = Date.now() + MATCH_WINDOW_MS;
    for (;;) {
      const outcome = await this.sweep(trip, favorites, riderInfo, deadline);
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
    await this.declareNoDrivers(trip);
  }

  /**
   * End a search that found nobody: [trip] leaves [from] (MATCHING, or
   * REQUESTED for a ride whose search never started) for no_drivers /
   * expired, and the rider is told. Returns false when the trip had already
   * moved on (accepted, cancelled) — nothing is done then.
   */
  async declareNoDrivers(
    trip: Pick<Trip, 'id' | 'riderId' | 'pickupLat' | 'pickupLng'>,
    from: TripStatus = TripStatus.matching,
  ): Promise<boolean> {
    const tripId = trip.id;
    try {
      await this.stateMachine.transition({
        tripId,
        from,
        to: from === TripStatus.matching ? TripStatus.no_drivers : TripStatus.expired,
        actor: 'system',
      });
    } catch {
      return false; // Trip left that state (accepted, cancelled) — nothing to do.
    }
    this.realtime.emitToUser(trip.riderId, 'trip:no_drivers', { tripId });
    void this.notifications.notifyTrip(trip.riderId, 'no_drivers', { tripId });
    // Unmet demand must not keep surging the cell for the next rider.
    await this.surge
      .releaseDemand(trip.pickupLat, trip.pickupLng, trip.riderId)
      .catch(() => undefined);
    return true;
  }

  /** Trips parked by the ops dispatch pause (waiting on purpose). */
  async deferredIds(): Promise<Set<string>> {
    return new Set(await this.redis.client.smembers(RedisKeys.dispatchDeferred()));
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
    riderInfo: RiderInfo,
    deadline: number,
  ): Promise<'assigned' | 'cancelled' | 'exhausted'> {
    const tried = new Set<string>();
    // A driver who explicitly declined this trip is never re-offered it — on
    // this sweep or a later one (the set lives in Redis so a retried job on
    // another node honours it too).
    const declined = await this.declinedSet(trip.id);
    const approach: ApproachCache = new Map();
    for (
      let radiusKm = START_RADIUS_KM;
      radiusKm <= MAX_RADIUS_KM;
      radiusKm += RADIUS_STEP_KM
    ) {
      let candidates = this.favoritesFirst(
        await this.nearestDrivers(trip, radiusKm),
        favorites,
      ).filter((id) => !declined.has(id));
      // On the closest ring, refine the crow-flies order into real road-ETA
      // order for the top few non-favourite candidates — nearest-by-road beats
      // nearest-as-the-crow-flies across rivers/highways. Bounded + fail-open.
      if (radiusKm === START_RADIUS_KM) {
        candidates = await this.rankByRoadEta(trip, candidates, favorites, approach);
      }
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
        if (await this.offerTo(driverId, trip, riderInfo, approach)) return 'assigned';
      }
    }
    return 'exhausted';
  }

  private async declinedSet(tripId: string): Promise<Set<string>> {
    try {
      const ids = await this.redis.client.smembers(RedisKeys.dispatchDeclined(tripId));
      return new Set(ids ?? []);
    } catch {
      return new Set();
    }
  }

  private async markDeclined(tripId: string, driverId: string): Promise<void> {
    const key = RedisKeys.dispatchDeclined(tripId);
    await this.redis.client.sadd(key, driverId);
    await this.redis.client.expire(key, DECLINED_TTL_S);
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

  /**
   * Refine the nearest non-favourite candidates from crow-flies order into real
   * road-ETA order (favourites still lead, untouched). Bounded to ETA_RANK_LIMIT
   * routing calls and fail-open: any error, or a provider without real routing,
   * just preserves the incoming order. Candidates with no computable route sort
   * last so a routable driver is always preferred.
   */
  private async rankByRoadEta(
    trip: Trip,
    candidates: string[],
    favorites: Set<string>,
    cache: ApproachCache = new Map(),
  ): Promise<string[]> {
    try {
      const favs = candidates.filter((id) => favorites.has(id));
      const rest = candidates.filter((id) => !favorites.has(id));
      const head = rest.slice(0, ETA_RANK_LIMIT);
      const tail = rest.slice(ETA_RANK_LIMIT);
      const withEta = await Promise.all(
        head.map(async (id) => {
          // Keep the route: the offer card reuses it (road ETA/distance)
          // instead of paying for a second routing call per offer.
          const route = await this.approachRoute(id, trip);
          cache.set(id, route);
          return { id, eta: route?.durationS ?? Infinity };
        }),
      );
      withEta.sort((a, b) => a.eta - b.eta);
      return [...favs, ...withEta.map((w) => w.id), ...tail];
    } catch {
      return candidates;
    }
  }

  /**
   * Seconds until the closest online driver of [tier] could reach [pickup]
   * (straight-line distance at a nominal urban pace, plus a minute of
   * pickup slack), or null when nobody is within 15 km. Drives the "N min
   * away" line on the rider's tier list; never throws.
   */
  async nearestDriverEtaS(
    pickup: { lat: number; lng: number },
    tier: string,
  ): Promise<number | null> {
    try {
      const result = (await this.redis.client.geosearch(
        RedisKeys.driversGeo(tier),
        'FROMLONLAT',
        pickup.lng,
        pickup.lat,
        'BYRADIUS',
        15,
        'km',
        'ASC',
        'COUNT',
        1,
        'WITHDIST',
      )) as [string, string][];
      if (result.length === 0) return null;
      const [driverId, distKm] = result[0];
      const alive = await this.evictStale(tier, [driverId]);
      if (alive.length === 0) return null;
      const metres = Number(distKm) * 1000;
      return Math.round(metres / FALLBACK_APPROACH_MPS) + 60;
    } catch {
      return null;
    }
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
      // A silent ghost is taken fully offline (Redis + DB) and *told* — the
      // app may still be showing "Online" (killed location updates, suspended
      // in the background) while we've stopped offering it trips. Best-effort;
      // never lets a presence hiccup break matching.
      await Promise.all(
        stale.map((id) =>
          this.drivers.forceOffline(id, tier, 'stale_location').catch(() => false),
        ),
      );
    }
    return fresh;
  }

  /** Offer to one driver under a lock; resolve when they accept/decline/expire. */
  private async offerTo(
    driverId: string,
    trip: Trip,
    riderInfo: RiderInfo,
    approach: ApproachCache = new Map(),
  ): Promise<boolean> {
    const lockKey = RedisKeys.driverOfferLock(driverId);
    const locked = await this.redis.client.set(
      lockKey,
      trip.id,
      'PX',
      OFFER_LOCK_TTL_MS,
      'NX',
    );
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

      // How far/long the driver must travel to reach the rider. Distinct from
      // distanceM/durationS, which are the *trip* leg. Road numbers come from
      // the route already computed for ranking; otherwise straight-line at a
      // nominal pace. Lets the driver judge the pickup before accepting.
      const { approachDistanceM, approachEtaS, approachSource } =
        await this.approachForOffer(driverId, trip, approach);

      this.realtime.emitToUser(driverId, 'trip:offer', {
        tripId: trip.id,
        pickup: { lat: trip.pickupLat, lng: trip.pickupLng, address: trip.pickupAddr },
        dropoff: { lat: trip.dropoffLat, lng: trip.dropoffLng, address: trip.dropoffAddr },
        fare: Number(trip.fareEstimate ?? 0),
        surge: Number(trip.surgeMultiplier ?? 1),
        tier: trip.tier,
        distanceM: trip.distanceM,
        durationS: trip.durationS,
        expiresInSec: OFFER_TTL_MS / 1000,
        rider: { name: riderInfo.name, rating: riderInfo.rating },
        pickupNote: trip.pickupNote ?? undefined,
        approachDistanceM,
        approachEtaS,
        approachSource,
      });

      const verdict = await this.awaitResponse(trip.id, driverId);
      await this.redis.client.del(RedisKeys.dispatchOffer(trip.id));
      this.metrics.offerOutcome(verdict === 'timeout' ? 'expired' : verdict);

      if (verdict !== 'accepted') {
        if (verdict === 'declined') {
          await this.markDeclined(trip.id, driverId).catch(() => undefined);
        }
        this.realtime.emitToUser(driverId, 'trip:offer_expired', { tripId: trip.id });
        return false;
      }
      const assigned = await this.assign(trip, driverId);
      if (!assigned) {
        // The driver tapped Accept but the trip could not be committed to them
        // (rider cancelled during the offer window, trip already taken, or the
        // driver is still bound to another trip). Without this the driver app
        // sits on the offer card with an infinite Accept spinner — it only ever
        // learned about the not-accepted branch above.
        this.realtime.emitToUser(driverId, 'trip:offer_expired', { tripId: trip.id });
      }
      return assigned;
    } finally {
      await this.redis.client.del(lockKey);
    }
  }

  /**
   * Wait for the offered driver's response by polling the Redis response key.
   * Cross-process: the accept/decline may be handled by another node — it lands
   * in Redis and we pick it up here. Resolves false on TTL timeout.
   */
  private async awaitResponse(
    tripId: string,
    driverId: string,
  ): Promise<'accepted' | 'declined' | 'timeout'> {
    const respKey = RedisKeys.dispatchResponse(tripId);
    const deadline = Date.now() + OFFER_TTL_MS;
    while (Date.now() < deadline) {
      const raw = await this.redis.client.get(respKey);
      if (raw !== null) {
        await this.redis.client.del(respKey);
        // Format "accepted:driverId" — ignore a response from a stale driver.
        const [verdict, who] = raw.split(':');
        if (who === driverId) return verdict === '1' ? 'accepted' : 'declined';
      }
      await this.sleep(RESPONSE_POLL_MS);
    }
    return 'timeout';
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
    if (offeree !== driverId) {
      if (accepted) {
        // A duplicate accept (double-tap, REST retry after the socket accept
        // already won) for a trip that IS this driver's must not be answered
        // with offer_expired — that would make the app drop a live trip.
        if (await this.isAssignedTo(tripId, driverId)) return true;
        // Otherwise the offer window closed (or the trip was never offered to
        // this driver): don't leave them waiting on an assignment that will
        // never come — tell them the offer is gone.
        this.realtime.emitToUser(driverId, 'trip:offer_expired', { tripId });
      }
      return false;
    }
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

  /** Is this trip already live with this driver (accepted/arrived/in_progress)? */
  private async isAssignedTo(tripId: string, driverId: string): Promise<boolean> {
    try {
      const t = await this.prisma.trip.findUnique({
        where: { id: tripId },
        select: { driverId: true, status: true },
      });
      return (
        !!t &&
        t.driverId === driverId &&
        (t.status === TripStatus.accepted ||
          t.status === TripStatus.arrived ||
          t.status === TripStatus.in_progress)
      );
    } catch {
      return false;
    }
  }

  private async assign(trip: Trip, driverId: string): Promise<boolean> {
    // Defence in depth against double-assignment: never commit a driver who is
    // already on another trip (e.g. if their offer lock expired early under a
    // long OFFER_TTL). The state-machine guard below is per-trip, not per-driver,
    // so this is the only thing stopping one driver holding two trips at once.
    const active = await this.redis.client.get(
      RedisKeys.driverActiveTrip(driverId),
    );
    if (active && active !== trip.id) return false;

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
    // Link the driver to this trip. completeTrip / cancel clear these keys
    // explicitly; the TTL is a safety net so a trip abandoned mid-ride (app
    // crash, socket gone, never completed) can't bench the driver forever —
    // `location.ingest` skips re-adding an on-trip driver to the pool, so a
    // stale linkage would otherwise keep them un-dispatchable indefinitely.
    // After the TTL the driver rejoins the pool on their next location ping.
    // Far longer than any real ride, so a legitimate trip is never evicted.
    const activeLinkTtlSeconds = 6 * 60 * 60; // 6 hours
    await this.redis.client.set(
      RedisKeys.driverActiveTrip(driverId),
      trip.id,
      'EX',
      activeLinkTtlSeconds,
    );
    await this.redis.client.set(
      RedisKeys.driverActiveRider(driverId),
      trip.riderId,
      'EX',
      activeLinkTtlSeconds,
    );

    const driver = await this.prisma.user.findUnique({
      where: { id: driverId },
      include: { driverProfile: true },
    });

    // Route from the driver's current position TO the pickup, so the rider's map
    // can draw the approach leg (driver → you) while the driver is en route,
    // instead of the trip route. Best-effort: if the driver's position is
    // unknown or routing fails, omit it and the client falls back to the trip
    // route. Provider-agnostic — uses whatever GeoProvider is configured.
    const approach = await this.approachRoute(driverId, trip);
    const driverPolyline = approach?.polyline || undefined;
    // Live "arriving in N min" + approach distance for the rider — derived from
    // the same approach route we already compute for the polyline, so this adds
    // no extra provider call. Undefined when the driver's position is unknown or
    // routing failed (older/degraded clients just won't show the countdown).
    const etaSec = approach?.durationS;
    const etaDistanceM = approach?.distanceM;

    // Navigation context for the approach leg: each GPS ping now carries a
    // cheap live ETA/remaining distance to the rider (see LocationService).
    await this.redis.client
      .hset(RedisKeys.tripNav(trip.id), {
        phase: 'approach',
        targetLat: trip.pickupLat,
        targetLng: trip.pickupLng,
        polyline: driverPolyline ?? '',
        avgSpeedMps:
          approach && approach.durationS > 0
            ? approach.distanceM / approach.durationS
            : '',
      })
      .catch(() => undefined);

    this.realtime.emitToUser(trip.riderId, 'trip:accepted', {
      tripId: trip.id,
      // Rider-only event: the start code is what they read to the driver. A
      // scheduled ride fires while the rider's screen has no trip loaded, so
      // it has to travel with the match.
      startOtp: trip.startOtp,
      driver: {
        id: driverId,
        name: driver?.fullName ?? 'Your driver',
        rating: Number(driver?.ratingAvg ?? 5),
        // The rider's "Call" button dials this. PILOT ONLY: this is the
        // driver's real number. Production must hand out a masked/proxy
        // number (per-trip telephony session) instead of users.phone.
        phone: driver?.phone ?? undefined,
      },
      vehicle: {
        make: driver?.driverProfile?.vehicleMake,
        model: driver?.driverProfile?.vehicleModel,
        color: driver?.driverProfile?.vehicleColor,
        plate: driver?.driverProfile?.plateNumber,
      },
      polyline: trip.routePolyline,
      driverPolyline,
      etaSec,
      etaDistanceM,
    });
    // A ride booked for somebody else: the booker gets the event above, but
    // they are not in the car. The passenger is the one who has to recognise
    // the vehicle and read the start code out, and they may have no app at
    // all — so it goes to them by text. Best-effort; a gateway failure must
    // not undo an assignment that has already happened.
    if (trip.passengerPhone) {
      const car = [
        driver?.driverProfile?.vehicleColor,
        driver?.driverProfile?.vehicleMake,
        driver?.driverProfile?.vehicleModel,
      ]
        .filter(Boolean)
        .join(' ');
      const plate = driver?.driverProfile?.plateNumber;
      const parts = [
        `${driver?.fullName ?? 'Your driver'} is on the way to collect you.`,
        car || plate ? `Look for a ${[car, plate].filter(Boolean).join(', ')}.` : '',
        `Your start code is ${trip.startOtp}.`,
      ].filter(Boolean);
      void this.sms
        .sendMessage(trip.passengerPhone, parts.join(' '))
        .catch((e: Error) =>
          this.logger.warn(
            `passenger SMS for trip ${trip.id} failed: ${e.message}`,
          ),
        );
    }

    // The driver needs the same geometry the rider gets: the approach leg
    // (their car → the pickup) so their map can show exactly where they're
    // collecting the rider from, plus the trip route for the on-trip leg. The
    // approach ETA/distance also lets the driver UI show "N min to pickup".
    this.realtime.emitToUser(driverId, 'trip:assigned', {
      tripId: trip.id,
      polyline: trip.routePolyline,
      driverPolyline,
      etaSec,
      etaDistanceM,
    });
    void this.notifications.notifyTrip(trip.riderId, 'accepted', {
      tripId: trip.id,
    });
    this.logger.log(`Trip ${trip.id} assigned to driver ${driverId}`);
    return true;
  }

  /**
   * Best-effort road route (polyline + duration + distance) from the driver's
   * last-known position to the trip pickup. Returns undefined if the position is
   * unknown or routing fails, so callers degrade gracefully (no approach line,
   * no live ETA) rather than erroring.
   */
  /**
   * Straight-line (haversine) distance in metres from the driver's last-known
   * position to the trip pickup. Undefined if the position is unknown. Cheap —
   * a single Redis read plus local math, safe to call per offer.
   */
  private async approachDistanceM(
    driverId: string,
    trip: Trip,
  ): Promise<number | undefined> {
    try {
      const [lat, lng] = await this.redis.client.hmget(
        RedisKeys.driverLoc(driverId),
        'lat',
        'lng',
      );
      const dlat = lat != null ? Number(lat) : NaN;
      const dlng = lng != null ? Number(lng) : NaN;
      if (!Number.isFinite(dlat) || !Number.isFinite(dlng)) return undefined;
      return Math.round(
        haversineMeters(
          { lat: dlat, lng: dlng },
          { lat: trip.pickupLat, lng: trip.pickupLng },
        ),
      );
    } catch {
      return undefined;
    }
  }

  /**
   * Offer-card approach numbers. Road ETA/distance when the ranking pass
   * already routed this driver (no extra provider call); otherwise the
   * straight-line distance and a nominal-pace ETA. Never throws.
   */
  private async approachForOffer(
    driverId: string,
    trip: Trip,
    cache: ApproachCache,
  ): Promise<{
    approachDistanceM?: number;
    approachEtaS?: number;
    approachSource: 'road' | 'straight' | 'unknown';
  }> {
    const route = cache.get(driverId);
    if (route) {
      return {
        approachDistanceM: Math.round(route.distanceM),
        approachEtaS: Math.round(route.durationS),
        approachSource: 'road',
      };
    }
    const straight = await this.approachDistanceM(driverId, trip);
    if (straight === undefined) return { approachSource: 'unknown' };
    return {
      approachDistanceM: straight,
      approachEtaS: Math.round(straight / FALLBACK_APPROACH_MPS),
      approachSource: 'straight',
    };
  }

  private async approachRoute(
    driverId: string,
    trip: Trip,
  ): Promise<RouteResult | undefined> {
    try {
      const [lat, lng] = await this.redis.client.hmget(
        RedisKeys.driverLoc(driverId),
        'lat',
        'lng',
      );
      const dlat = lat != null ? Number(lat) : NaN;
      const dlng = lng != null ? Number(lng) : NaN;
      if (!Number.isFinite(dlat) || !Number.isFinite(dlng)) return undefined;
      return await this.geo.route(
        { lat: dlat, lng: dlng },
        { lat: trip.pickupLat, lng: trip.pickupLng },
      );
    } catch {
      return undefined;
    }
  }
}
