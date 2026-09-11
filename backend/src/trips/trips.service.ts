import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { RideTier, Trip, TripStatus } from '@prisma/client';
import { randomInt, timingSafeEqual } from 'node:crypto';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import {
  GEO_PROVIDER,
  GeoProvider,
  LatLng,
  RouteResult,
} from '../geo/geo-provider.interface';
import { encodePolyline } from '../geo/geo.util';
import { StopDto } from './dto/stop.dto';
import { CURRENCY } from '../pricing/fare-config';
import { PricingService } from '../pricing/pricing.service';
import { SurgeService } from '../surge/surge.service';
import { ComparisonService } from '../comparison/comparison.service';
import { PromoService } from '../promo/promo.service';
import {
  MAX_LEAD_MS,
  MIN_LEAD_MS,
  ScheduledService,
} from '../scheduled/scheduled.service';
import { RealtimeService } from '../realtime/realtime.service';
import { DispatchService } from '../dispatch/dispatch.service';
import { PaymentsService } from '../payments/payments.service';
import { NotificationsService } from '../notifications/notifications.service';
import { EmailService } from '../email/email.service';
import { CreateTripDto } from './dto/create-trip.dto';
import { EstimateDto } from './dto/estimate.dto';
import { TripStateMachine } from './trip-state-machine';

const CANCELLABLE: TripStatus[] = [
  TripStatus.scheduled,
  TripStatus.requested,
  TripStatus.matching,
  TripStatus.accepted,
  TripStatus.arrived,
];

/** A driver may walk away from a ride only before it starts. */
const DRIVER_CANCELLABLE: TripStatus[] = [
  TripStatus.accepted,
  TripStatus.arrived,
];

/** Statuses in which a rider already has a ride in flight: a second request
 *  is refused (409) until this one ends. `scheduled` is excluded — a rider may
 *  book a future ride while on (or waiting for) the current one. */
export const ACTIVE_TRIP_STATUSES: TripStatus[] = [
  TripStatus.requested,
  TripStatus.matching,
  TripStatus.accepted,
  TripStatus.arrived,
  TripStatus.in_progress,
];

/** Start-code brute-force guard: 4 digits = 10k codes, so bound the guesses
 *  per trip and lock the trip for a cooling-off period once exhausted. */
export const OTP_MAX_ATTEMPTS = 5;
export const OTP_LOCK_SECONDS = 15 * 60;
const otpAttemptsKey = (tripId: string) => `trip:${tripId}:otpAttempts`;
const otpLockKey = (tripId: string) => `trip:${tripId}:otpLock`;

/** No cancellation fee within this window after a driver accepts — the rider
 *  gets a moment to change their mind before the driver has invested. */
export const CANCEL_GRACE_MS = 2 * 60 * 1000;

/** Bounds on the metered final fare relative to the up-front (gross) estimate.
 *  The odometer is fed by driver-supplied GPS, so it must not be able to push
 *  the fare arbitrarily above what the rider agreed to — or collapse it. */
export const FARE_CLAMP_MIN = 0.8;
export const FARE_CLAMP_MAX = 1.5;

@Injectable()
export class TripsService {
  private readonly logger = new Logger('TripsService');

  constructor(
    private readonly prisma: PrismaService,
    private readonly pricing: PricingService,
    private readonly surge: SurgeService,
    private readonly promo: PromoService,
    private readonly scheduled: ScheduledService,
    private readonly stateMachine: TripStateMachine,
    private readonly redis: RedisService,
    private readonly realtime: RealtimeService,
    private readonly dispatch: DispatchService,
    private readonly payments: PaymentsService,
    private readonly notifications: NotificationsService,
    private readonly email: EmailService,
    private readonly config: ConfigService,
    private readonly comparison: ComparisonService,
    @Inject(GEO_PROVIDER) private readonly geo: GeoProvider,
  ) {}

  /** Route + fare estimate for every tier (what the rider picks from). */
  async estimate(dto: EstimateDto) {
    const pickup: LatLng = { lat: dto.pickupLat, lng: dto.pickupLng };
    const dropoff: LatLng = { lat: dto.dropoffLat, lng: dto.dropoffLng };
    const route = await this.routeFor(pickup, dropoff, dto.stops);
    const surge = await this.surge.multiplierFor(pickup.lat, pickup.lng);
    return {
      distanceM: route.distanceM,
      durationS: route.durationS,
      polyline: route.polyline,
      surge,
      currency: CURRENCY,
      pickup,
      dropoff,
      stops: dto.stops ?? [],
      tiers: this.pricing.estimateAllTiers(route.distanceM, route.durationS, surge),
      // How our economy fare stacks up against modeled Uber/Lyft/Empower prices
      // for this exact trip, with the cheapest provider flagged. Reuses the
      // already-routed distance/time — no extra routing call.
      comparison: this.comparison.compare(
        route.distanceM,
        route.durationS,
        surge,
        'economy',
      ),
    };
  }

  /**
   * Route for a trip: a direct pickup→dropoff route when there are no stops
   * (keeps the provider's real polyline), otherwise the summed legs through
   * every waypoint (distance/duration are the totals; the polyline is a
   * multi-segment line through the waypoints).
   */
  private async routeFor(
    pickup: LatLng,
    dropoff: LatLng,
    stops?: StopDto[],
  ): Promise<RouteResult> {
    if (!stops || stops.length === 0) {
      return this.geo.route(pickup, dropoff);
    }
    const points: LatLng[] = [
      pickup,
      ...stops.map((s) => ({ lat: s.lat, lng: s.lng })),
      dropoff,
    ];
    let distanceM = 0;
    let durationS = 0;
    for (let i = 0; i < points.length - 1; i++) {
      const leg = await this.geo.route(points[i], points[i + 1]);
      distanceM += leg.distanceM;
      durationS += leg.durationS;
    }
    return { distanceM, durationS, polyline: encodePolyline(points) };
  }

  /**
   * Create a trip. Normally lands in REQUESTED and dispatches immediately; when
   * `scheduledAt` is set (and far enough ahead), it lands in SCHEDULED and a
   * delayed job promotes it to a live request at the scheduled time.
   */
  async createTrip(riderId: string, dto: CreateTripDto) {
    const scheduledAt = this.parseSchedule(dto.scheduledAt);
    // One live ride per rider. Without this a rider (or a retrying client)
    // can pile up concurrent requested/matching trips that each burn dispatch
    // offers. A scheduled-for-later booking is allowed alongside a live one.
    if (!scheduledAt) {
      const inFlight = await this.prisma.trip.findFirst({
        where: { riderId, status: { in: ACTIVE_TRIP_STATUSES } },
        select: { id: true, status: true },
      });
      if (inFlight) {
        throw new ConflictException(
          `You already have a ride in progress (${inFlight.status}). Cancel it or wait for it to finish before requesting another.`,
        );
      }
    }
    // The chosen saved card must belong to this rider; otherwise (or when
    // none is chosen) the default card is charged.
    const paymentMethodId = await this.resolvePaymentMethod(
      riderId,
      dto.paymentMethodId,
    );
    const pickup: LatLng = { lat: dto.pickupLat, lng: dto.pickupLng };
    const dropoff: LatLng = { lat: dto.dropoffLat, lng: dto.dropoffLng };
    const route = await this.routeFor(pickup, dropoff, dto.stops);
    const surge = await this.surge.multiplierFor(pickup.lat, pickup.lng);
    const est = this.pricing.estimateForTier(
      dto.tier,
      route.distanceM,
      route.durationS,
      surge,
    );

    const initialStatus = scheduledAt
      ? TripStatus.scheduled
      : TripStatus.requested;

    let trip = await this.prisma.trip.create({
      data: {
        riderId,
        status: initialStatus,
        tier: dto.tier as RideTier,
        pickupAddr: dto.pickupAddr,
        pickupLat: dto.pickupLat,
        pickupLng: dto.pickupLng,
        dropoffAddr: dto.dropoffAddr,
        dropoffLat: dto.dropoffLat,
        dropoffLng: dto.dropoffLng,
        routePolyline: route.polyline,
        stops: dto.stops && dto.stops.length > 0 ? (dto.stops as object[]) : undefined,
        distanceM: route.distanceM,
        durationS: route.durationS,
        fareEstimate: est.fare,
        surgeMultiplier: surge,
        currency: CURRENCY,
        startOtp: this.generateOtp(),
        paymentMode: dto.paymentMode ?? 'card',
        paymentMethodId,
        scheduledAt,
      },
    });

    // Apply a promo code (if supplied) against the gross estimate. Redemption is
    // atomic and linked to this trip; the discount is stored so settleFare can
    // subtract it from the final recomputed fare too. A bad/expired code yields
    // no discount rather than failing the ride.
    if (dto.promoCode) {
      const discount = await this.promo.redeem(
        dto.promoCode,
        est.fare,
        riderId,
        trip.id,
      );
      if (discount > 0) {
        trip = await this.prisma.trip.update({
          where: { id: trip.id },
          data: {
            promoCode: dto.promoCode.trim().toUpperCase(),
            promoDiscount: discount,
            fareEstimate: Math.max(est.fare - discount, 0),
          },
        });
      }
    }

    // Initial audit event (creation: null -> scheduled|requested).
    await this.prisma.tripEvent.create({
      data: {
        tripId: trip.id,
        fromStatus: null,
        toStatus: initialStatus,
        actor: 'rider',
        meta: { tier: dto.tier, scheduledAt: scheduledAt?.toISOString() ?? null },
      },
    });

    if (scheduledAt) {
      // Defer matching until the scheduled time; demand is recorded then, not now.
      await this.scheduled.enqueue(trip.id, scheduledAt);
      return this.serialize(trip);
    }

    // This request now contributes to local demand (raising surge for the next
    // riders in the same area until it decays).
    await this.surge.recordDemand(dto.pickupLat, dto.pickupLng);

    // Kick off matching without blocking the response (rider sees REQUESTED,
    // then MATCHING/ACCEPTED arrive over the socket).
    void this.dispatch
      .dispatchTrip(trip.id)
      .catch(() => undefined);

    return this.serialize(trip);
  }

  /**
   * Validates a rider-supplied saved-card id: it must be one of the rider's
   * own methods. Returns the id to persist, or null (= default card) when none
   * was supplied. A card belonging to someone else is a 400, not silently
   * swapped for the default.
   */
  private async resolvePaymentMethod(
    riderId: string,
    paymentMethodId?: string,
  ): Promise<string | null> {
    if (!paymentMethodId) return null;
    const method = await this.prisma.paymentMethod.findFirst({
      where: { id: paymentMethodId, userId: riderId },
      select: { id: true },
    });
    if (!method) {
      throw new BadRequestException('Unknown payment method');
    }
    return method.id;
  }

  /**
   * Validates and parses a requested schedule time. Returns null for an
   * on-demand ride, or throws if the time is too soon or too far ahead.
   */
  private parseSchedule(iso?: string): Date | null {
    if (!iso) return null;
    const when = new Date(iso);
    const lead = when.getTime() - Date.now();
    if (!Number.isFinite(when.getTime()) || lead < MIN_LEAD_MS) {
      throw new BadRequestException(
        'Scheduled rides must be at least 5 minutes ahead.',
      );
    }
    if (lead > MAX_LEAD_MS) {
      throw new BadRequestException(
        'Rides can be scheduled up to 30 days ahead.',
      );
    }
    return when;
  }

  // --- Driver-side lifecycle (Phase 2) ---

  async driverArrived(driverId: string, tripId: string) {
    const trip = await this.assertDriverTrip(driverId, tripId, TripStatus.accepted);
    await this.stateMachine.transition({
      tripId,
      from: TripStatus.accepted,
      to: TripStatus.arrived,
      actor: 'driver',
      data: { arrivedAt: new Date() },
    });
    this.realtime.emitToUser(trip.riderId, 'trip:arrived', { tripId });
    void this.notifications.notifyTrip(trip.riderId, 'arrived', { tripId });
    return { status: TripStatus.arrived };
  }

  async startTrip(driverId: string, tripId: string, otp: string) {
    const trip = await this.assertDriverTrip(driverId, tripId, TripStatus.arrived);
    await this.verifyStartOtp(trip, otp);
    await this.stateMachine.transition({
      tripId,
      from: TripStatus.arrived,
      to: TripStatus.in_progress,
      actor: 'driver',
      data: { startedAt: new Date() },
    });
    // Seed the trip odometer so LocationService starts metering driven distance.
    // Seeded from the driver's current position so the first segment counts.
    const loc = await this.redis.client.hgetall(RedisKeys.driverLoc(driverId));
    await this.redis.client.set(RedisKeys.tripDriven(tripId), '0');
    if (loc?.lat && loc?.lng) {
      await this.redis.client.hset(RedisKeys.tripMeterLast(tripId), {
        lat: loc.lat,
        lng: loc.lng,
        ts: Date.now(),
      });
    }
    // Auth-hold the estimated fare when the ride starts (manual capture).
    await this.payments.authorizeForTrip(tripId).catch((e) =>
      // Don't block the ride on a payment hiccup; capture will retry on complete.
      this.realtime.emitToUser(trip.riderId, 'trip:payment_warning', {
        tripId,
        message: 'Payment could not be processed',
      }),
    );
    this.realtime.emitToUser(trip.riderId, 'trip:started', { tripId });
    void this.notifications.notifyTrip(trip.riderId, 'started', { tripId });
    return { status: TripStatus.in_progress };
  }

  /**
   * Constant-time start-code check with a per-trip attempt budget. After
   * OTP_MAX_ATTEMPTS wrong guesses the trip is locked for OTP_LOCK_SECONDS and
   * the rider is told (a driver guessing codes is a signal worth surfacing).
   * A correct code clears the counter.
   */
  private async verifyStartOtp(trip: Trip, otp: string): Promise<void> {
    const lockKey = otpLockKey(trip.id);
    const attemptsKey = otpAttemptsKey(trip.id);
    if (await this.redis.client.get(lockKey)) {
      throw new BadRequestException(
        'Too many incorrect start codes. Ask the rider to confirm the code and try again in a few minutes.',
      );
    }
    const expected = Buffer.from(trip.startOtp ?? '', 'utf8');
    const supplied = Buffer.from(String(otp ?? ''), 'utf8');
    const matches =
      expected.length > 0 &&
      expected.length === supplied.length &&
      timingSafeEqual(expected, supplied);
    if (matches) {
      await this.redis.client.del(attemptsKey);
      return;
    }
    const attempts = await this.redis.client.incr(attemptsKey);
    await this.redis.client.expire(attemptsKey, OTP_LOCK_SECONDS);
    if (attempts >= OTP_MAX_ATTEMPTS) {
      await this.redis.client.set(lockKey, '1', 'EX', OTP_LOCK_SECONDS);
      await this.redis.client.del(attemptsKey);
      this.realtime.emitToUser(trip.riderId, 'trip:otp_locked', {
        tripId: trip.id,
        lockSeconds: OTP_LOCK_SECONDS,
      });
      void this.notifications.notify(trip.riderId, {
        title: 'Start code locked',
        body: 'Your driver entered the wrong start code too many times. Share the code only with your driver.',
        data: { kind: 'otp_locked', tripId: trip.id },
      });
      throw new BadRequestException(
        'Too many incorrect start codes. Try again in 15 minutes.',
      );
    }
    throw new BadRequestException(
      `Incorrect start code (${OTP_MAX_ATTEMPTS - attempts} attempts left)`,
    );
  }

  async completeTrip(driverId: string, tripId: string) {
    const trip = await this.assertDriverTrip(
      driverId,
      tripId,
      TripStatus.in_progress,
    );
    // Recompute the final fare from the actually-driven distance (the trip
    // odometer accumulated by LocationService), falling back to the estimate
    // when there's no usable GPS trail (e.g. simulator with sparse pings).
    const { fareFinal, distanceM, durationS } = await this.settleFare(trip);
    await this.stateMachine.transition({
      tripId,
      from: TripStatus.in_progress,
      to: TripStatus.completed,
      actor: 'driver',
      data: { completedAt: new Date(), fareFinal, distanceM, durationS },
    });

    // Release the driver back to the available pool.
    await this.redis.client.set(RedisKeys.driverStatus(driverId), 'online');
    await this.redis.client.del(
      RedisKeys.driverActiveTrip(driverId),
      RedisKeys.driverActiveRider(driverId),
    );
    await this.prisma.driverProfile.update({
      where: { userId: driverId },
      data: { totalTrips: { increment: 1 } },
    });

    // Capture the fare and compute the platform-fee / driver-payout split. If
    // the capture fails the ride still happened, so: queue a durable retry
    // (PaymentsProcessor, with backoff; captureForTrip is idempotent) and hand
    // out a receipt that says the payment is PENDING — never a made-up split
    // the ledger did not record (the old fallback reported the whole fare as
    // driver payout with zero platform fee).
    let split: {
      fareFinal: number;
      platformFee: number | null;
      driverPayout: number | null;
    };
    let paymentStatus: 'captured' | 'pending';
    try {
      split = await this.payments.captureForTrip(tripId);
      paymentStatus = 'captured';
    } catch (e) {
      this.logger.warn(
        `capture failed at completion for trip ${tripId}, queueing retry: ${String(e)}`,
      );
      paymentStatus = 'pending';
      split = { fareFinal: Number(fareFinal), platformFee: null, driverPayout: null };
      await this.payments.enqueueCapture(tripId).catch((qe) =>
        this.logger.error(`could not enqueue capture retry for ${tripId}: ${String(qe)}`),
      );
      this.realtime.emitToUser(trip.riderId, 'trip:payment_warning', {
        tripId,
        message: 'Payment could not be processed yet; we will retry.',
      });
    }

    const receipt = {
      tripId,
      fareFinal: split.fareFinal,
      platformFee: split.platformFee,
      driverPayout: split.driverPayout,
      currency: trip.currency,
      distanceM,
      durationS,
      paymentMode: trip.paymentMode,
      paymentStatus,
    };
    this.realtime.emitToUser(trip.riderId, 'trip:completed', receipt);
    this.realtime.emitToUser(driverId, 'trip:completed', receipt);
    void this.notifications.notifyTrip(trip.riderId, 'completed', { tripId });
    void this.notifications.notifyTrip(driverId, 'completed', { tripId });
    // Best-effort emailed receipt (SES when keyed, mock otherwise). Never blocks
    // or fails the completion — EmailService swallows its own errors. When the
    // capture is still pending the processor sends it once the fare lands.
    if (paymentStatus === 'captured') {
      void (async () => {
        const rider = await this.prisma.user.findUnique({
          where: { id: trip.riderId },
          select: { email: true },
        });
        await this.email.sendReceipt(rider?.email, tripId, split.fareFinal);
      })();
    }
    return receipt;
  }

  /**
   * Determines the final fare at completion. Reads the trip odometer (actual
   * driven meters accumulated by LocationService) and, if it's usable,
   * recomputes the fare from real distance + wall-clock duration via pricing.
   * Falls back to the up-front estimate when there's no meaningful GPS trail.
   * Always clears the odometer keys.
   */
  private async settleFare(trip: Trip): Promise<{
    fareFinal: number;
    distanceM: number | null;
    durationS: number | null;
  }> {
    const drivenRaw = await this.redis.client.get(RedisKeys.tripDriven(trip.id));
    await this.redis.client.del(
      RedisKeys.tripDriven(trip.id),
      RedisKeys.tripMeterLast(trip.id),
    );
    const estimate = trip.fareEstimate ? Number(trip.fareEstimate) : 0;
    const driven = drivenRaw ? Number(drivenRaw) : 0;

    // Need a meaningful trail (>= 50 m) to trust the odometer over the estimate.
    if (!Number.isFinite(driven) || driven < 50) {
      return {
        fareFinal: estimate,
        distanceM: trip.distanceM,
        durationS: trip.durationS,
      };
    }

    const distanceM = Math.round(driven);
    const durationS = trip.startedAt
      ? Math.max(1, Math.round((Date.now() - trip.startedAt.getTime()) / 1000))
      : trip.durationS;
    const surge = trip.surgeMultiplier ? Number(trip.surgeMultiplier) : 1;
    const metered = this.pricing.estimateForTier(
      trip.tier,
      distanceM,
      durationS ?? 0,
      surge,
    ).fare;
    // Carry the up-front promo discount onto the final (odometer-based) fare.
    const discount = trip.promoDiscount ? Number(trip.promoDiscount) : 0;
    // `fareEstimate` is stored net of the promo; the clamp is on gross fares.
    const grossEstimate = estimate + discount;
    const gross = this.clampFare(metered, grossEstimate, trip.tier);
    const fareFinal = Math.max(gross - discount, 0);
    return { fareFinal, distanceM, durationS };
  }

  /**
   * Bound a metered (GPS-derived, driver-supplied) gross fare to
   * [FARE_CLAMP_MIN, FARE_CLAMP_MAX] × the gross up-front estimate, then floor
   * at the tier's minimum fare. Without a usable estimate the metered fare is
   * only floored.
   */
  private clampFare(metered: number, grossEstimate: number, tier: string): number {
    let fare = metered;
    if (grossEstimate > 0) {
      fare = Math.min(
        Math.max(fare, grossEstimate * FARE_CLAMP_MIN),
        grossEstimate * FARE_CLAMP_MAX,
      );
    }
    fare = Math.max(fare, this.pricing.minFareFor(tier));
    return Math.round(fare * 100) / 100;
  }

  private async assertDriverTrip(
    driverId: string,
    tripId: string,
    expected: TripStatus,
  ): Promise<Trip> {
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) throw new NotFoundException('Trip not found');
    if (trip.driverId !== driverId) {
      throw new ForbiddenException('Not your trip');
    }
    if (trip.status !== expected) {
      throw new BadRequestException(
        `Trip is ${trip.status}, expected ${expected}`,
      );
    }
    return trip;
  }

  async getTrip(userId: string, tripId: string) {
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) throw new NotFoundException('Trip not found');
    if (trip.riderId !== userId && trip.driverId !== userId) {
      throw new ForbiddenException('Not your trip');
    }
    return this.serialize(trip, userId);
  }

  /** The caller's current non-terminal trip (as rider or driver), or null.
   *  Lets an app that was killed/reopened mid-trip restore its live screen
   *  instead of showing an idle home while a ride is still in flight. */
  async getActiveTrip(userId: string) {
    const trip = await this.prisma.trip.findFirst({
      where: {
        OR: [{ riderId: userId }, { driverId: userId }],
        status: {
          in: [
            TripStatus.requested,
            TripStatus.matching,
            TripStatus.accepted,
            TripStatus.arrived,
            TripStatus.in_progress,
          ],
        },
      },
      orderBy: { requestedAt: 'desc' },
    });
    return trip ? this.serialize(trip, userId) : null;
  }

  async cancelTrip(userId: string, tripId: string, reason?: string) {
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) throw new NotFoundException('Trip not found');
    if (trip.riderId !== userId) {
      throw new ForbiddenException('Only the rider can cancel this trip');
    }
    if (!CANCELLABLE.includes(trip.status)) {
      throw new BadRequestException(
        `Trip in status ${trip.status} cannot be cancelled`,
      );
    }

    await this.stateMachine.transition({
      tripId,
      from: trip.status,
      to: TripStatus.cancelled,
      actor: 'rider',
      data: { cancelReason: reason ?? null, cancelledBy: 'rider' },
      meta: { reason: reason ?? null },
    });

    // A fee applies only once a driver has committed (accepted/arrived) — a
    // late cancel wastes the driver's trip to the pickup — and only after a
    // short grace window from acceptance (no fee if acceptedAt is unknown).
    const feeApplies = this.cancellationFeeApplies(trip);

    // If a driver was already assigned, notify them and return them to the pool.
    if (trip.driverId) {
      this.realtime.emitToUser(trip.driverId, 'trip:cancelled', {
        tripId,
        by: 'rider',
        reason: reason ?? null,
      });
      void this.notifications.notifyTrip(trip.driverId, 'cancelled', { tripId });
      await this.releaseDriver(trip.driverId);
    }
    await this.releasePromo(trip);

    let fee = 0;
    if (feeApplies) {
      const amount = this.config.get<number>('cancellationFee') ?? 5;
      try {
        fee = await this.payments.chargeCancellationFee(tripId, amount);
      } catch (e) {
        this.realtime.emitToUser(userId, 'trip:payment_warning', {
          tripId,
          message: 'Payment could not be processed',
        });
      }
    }

    return { status: TripStatus.cancelled, fee };
  }

  /**
   * Driver-side cancel (rider no-show, can't reach the pickup, ...). Only the
   * assigned driver, only before the ride starts, reason required. No rider
   * fee — the driver walked away. The driver is released back to the pool and
   * the rider is told (with the reason) so they can request again. The trip is
   * marked cancelled rather than re-dispatched: the dispatch job is keyed per
   * trip and the state machine has no accepted→requested edge, so re-opening
   * is not a clean operation here.
   */
  async driverCancelTrip(driverId: string, tripId: string, reason: string) {
    const trimmed = (reason ?? '').trim();
    if (!trimmed) throw new BadRequestException('A reason is required');
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) throw new NotFoundException('Trip not found');
    if (trip.driverId !== driverId) {
      throw new ForbiddenException('Not your trip');
    }
    if (!DRIVER_CANCELLABLE.includes(trip.status)) {
      throw new BadRequestException(
        `Trip in status ${trip.status} cannot be cancelled by the driver`,
      );
    }

    await this.stateMachine.transition({
      tripId,
      from: trip.status,
      to: TripStatus.cancelled,
      actor: 'driver',
      data: { cancelReason: trimmed, cancelledBy: 'driver' },
      meta: { reason: trimmed, driverId },
    });

    await this.releaseDriver(driverId);
    await this.releasePromo(trip);

    this.realtime.emitToUser(trip.riderId, 'trip:cancelled', {
      tripId,
      by: 'driver',
      reason: trimmed,
    });
    void this.notifications.notifyTrip(trip.riderId, 'cancelled', { tripId });
    this.realtime.emitToUser(driverId, 'trip:cancelled', {
      tripId,
      by: 'driver',
      reason: trimmed,
    });

    return { status: TripStatus.cancelled, fee: 0 };
  }

  /** Whether a rider cancel is charged: driver committed AND grace elapsed. */
  private cancellationFeeApplies(trip: Trip): boolean {
    const committed =
      trip.status === TripStatus.accepted || trip.status === TripStatus.arrived;
    if (!committed) return false;
    if (!trip.acceptedAt) return false;
    return Date.now() - trip.acceptedAt.getTime() >= CANCEL_GRACE_MS;
  }

  /** Return a driver to the available pool (clears their active-trip keys). */
  private async releaseDriver(driverId: string): Promise<void> {
    await this.redis.client.set(RedisKeys.driverStatus(driverId), 'online');
    await this.redis.client.del(
      RedisKeys.driverActiveTrip(driverId),
      RedisKeys.driverActiveRider(driverId),
    );
  }

  /** Hand back a promo redemption on a trip that never completed. */
  private async releasePromo(trip: Trip): Promise<void> {
    if (!trip.promoCode) return;
    try {
      await this.promo.release(trip.id);
    } catch (e) {
      this.logger.warn(`promo release failed for trip ${trip.id}: ${String(e)}`);
    }
  }

  async history(userId: string) {
    const trips = await this.prisma.trip.findMany({
      where: { OR: [{ riderId: userId }, { driverId: userId }] },
      orderBy: { requestedAt: 'desc' },
      take: 50,
    });
    return trips.map((t) => this.serialize(t, userId));
  }

  /** The rider's upcoming scheduled rides, soonest first. */
  async listScheduled(userId: string) {
    const trips = await this.prisma.trip.findMany({
      where: { riderId: userId, status: TripStatus.scheduled },
      orderBy: { scheduledAt: 'asc' },
    });
    return trips.map((t) => this.serialize(t, userId));
  }

  private generateOtp(): string {
    return Array.from({ length: 4 }, () => randomInt(0, 10)).join('');
  }

  private serialize(t: Trip, viewerId?: string) {
    // The rider sees the start OTP (to read to the driver); the driver enters
    // it, so it's hidden from the driver's view.
    const showOtp = viewerId === undefined || viewerId === t.riderId;
    return {
      id: t.id,
      riderId: t.riderId,
      driverId: t.driverId,
      status: t.status,
      tier: t.tier,
      pickup: { lat: t.pickupLat, lng: t.pickupLng, address: t.pickupAddr },
      dropoff: { lat: t.dropoffLat, lng: t.dropoffLng, address: t.dropoffAddr },
      stops: (t.stops as unknown[]) ?? [],
      routePolyline: t.routePolyline,
      distanceM: t.distanceM,
      durationS: t.durationS,
      fareEstimate: t.fareEstimate ? Number(t.fareEstimate) : null,
      fareFinal: t.fareFinal ? Number(t.fareFinal) : null,
      promoCode: t.promoCode,
      promoDiscount: Number(t.promoDiscount),
      paymentMode: t.paymentMode,
      scheduledAt: t.scheduledAt,
      surgeMultiplier: Number(t.surgeMultiplier),
      currency: t.currency,
      startOtp: showOtp ? t.startOtp : null,
      requestedAt: t.requestedAt,
      acceptedAt: t.acceptedAt,
      arrivedAt: t.arrivedAt,
      startedAt: t.startedAt,
      completedAt: t.completedAt,
    };
  }
}
