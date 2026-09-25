import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
  Optional,
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
import {
  SMS_PROVIDER,
  SmsProvider,
} from '../auth/sms/sms-provider.interface';
import { haversineMeters } from '../geo/geo.util';
import { StopDto } from './dto/stop.dto';
import { roundFare } from '../common/money';
import { CURRENCY } from '../pricing/fare-config';
import { FareBreakdown, PricingService } from '../pricing/pricing.service';
import { SurgeService } from '../surge/surge.service';
import {
  COMPETITOR_MODELS_CURRENCY,
  ComparisonService,
} from '../comparison/comparison.service';
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
import { BRAND_NAME } from '../common/brand';
import { routeThrough } from './route-through';
import { recordOfferEvent } from '../incentives/offer-events';
import { QuestsService } from '../incentives/quests.service';

const CANCELLABLE: TripStatus[] = [
  TripStatus.scheduled,
  TripStatus.requested,
  TripStatus.matching,
  TripStatus.accepted,
  TripStatus.arrived,
];

/** Statuses in which rider and driver can phone each other: from the match
 *  until the ride ends. Outside this window neither number is exposed. */
const CONTACTABLE: TripStatus[] = [
  TripStatus.accepted,
  TripStatus.arrived,
  TripStatus.in_progress,
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
/** Same freshness bar dispatch uses to evict ghost drivers from the pool. */
const PRESENCE_STALE_MS = Number(process.env.PRESENCE_STALE_MS ?? 45000);
const otpAttemptsKey = (tripId: string) => `trip:${tripId}:otpAttempts`;
const otpLockKey = (tripId: string) => `trip:${tripId}:otpLock`;

/** No cancellation fee within this window after a driver accepts — the rider
 *  gets a moment to change their mind before the driver has invested. */
export const CANCEL_GRACE_MS = 2 * 60 * 1000;

/** How long a driver waits at the pickup (from "Arrived") before they may
 *  cancel as a rider no-show and be paid the cancellation fee. */
export const NO_SHOW_WAIT_SEC = Number(process.env.NO_SHOW_WAIT_SEC ?? 300);

/** Bounds on the metered final fare relative to the up-front (gross) estimate.
 *  The odometer is fed by driver-supplied GPS, so it must not be able to push
 *  the fare arbitrarily above what the rider agreed to — or collapse it. */
export const FARE_CLAMP_MIN = 0.8;
export const FARE_CLAMP_MAX = 1.5;

/** Price lock: a quoted fare is honoured if the server's recomputed fare is
 *  within this fraction of it (and the surge multiplier is unchanged). */
export const PRICE_LOCK_TOLERANCE = 0.05;

/** A driver's last GPS fix older than this is not trusted for the arrival
 *  geofence (the check is skipped rather than blocking on stale data). */
export const ARRIVAL_FIX_MAX_AGE_MS = 60_000;

/** Itemised fare shown on the receipt (`trip:completed` + GET receipt). */
export interface ReceiptBreakdown extends FareBreakdown {
  promoDiscount: number;
  tip: number;
  /** Top-up applied when the metered components fell below the tier's
   *  minimum fare, so the itemised lines always add up to the headline. */
  minimumFareAdjustment: number;
  /** Signed move from the metered components to the charged fare when the
   *  [FARE_CLAMP_MIN, FARE_CLAMP_MAX] × estimate bound (or the up-front
   *  fallback) applied — NOT a minimum-fare top-up. 0 when metered as-is. */
  fareAdjustment: number;
  /** How the headline was reached, so apps word it truthfully:
   *  metered  — distance + time actually driven;
   *  minimum  — the tier's minimum fare (metered parts fell below it);
   *  estimate — bounded by / fell back to the up-front estimate. */
  fareBasis: FareBasis;
  /** The driver ended the trip away from the drop-off (with a reason). */
  endedEarly: boolean;
  endReason?: string;
  /** Where the trip ended, when that was away from the drop-off (metres). */
  endedAwayFromDropoffM?: number;
}

export type FareBasis = 'metered' | 'minimum' | 'estimate';

/** Odometer below this is "no usable GPS trail". */
export const MIN_TRAIL_M = 50;

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
    @Inject(SMS_PROVIDER) private readonly sms: SmsProvider,
    @Optional() private readonly quests?: QuestsService,
  ) {}

  /** Text the passenger of a ride somebody else booked. Best-effort: they are
   *  not the account holder and may not have the app, so SMS is the only way
   *  to reach them — but a gateway failure must never take the ride down. */
  private notifyPassenger(trip: Trip, message: string): void {
    if (!trip.passengerPhone) return;
    void this.sms
      .sendMessage(trip.passengerPhone, message)
      .catch((e: Error) =>
        this.logger.warn(
          `passenger SMS for trip ${trip.id} failed: ${e.message}`,
        ),
      );
  }

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
      // `etaSeconds` is how soon a car could be at the pickup (nearest online
      // driver of that tier), null when none is around; the trip's own
      // duration is a separate number.
      tiers: await Promise.all(
        this.pricing
          .estimateAllTiers(route.distanceM, route.durationS, surge)
          .map(async (t) => ({
            ...t,
            etaSeconds: await this.dispatch.nearestDriverEtaS(pickup, t.tier),
            tripDurationS: route.durationS,
          })),
      ),
      // How our economy fare stacks up against modeled Uber/Lyft/Empower prices
      // for this exact trip, with the cheapest provider flagged. Reuses the
      // already-routed distance/time — no extra routing call. Only where the
      // competitor rate cards were calibrated: they are US dollar fares, and
      // compared against rupees or som they would claim savings that are not
      // real. Null elsewhere — the app then shows no comparison card.
      comparison:
        CURRENCY === COMPETITOR_MODELS_CURRENCY
          ? this.comparison.compare(route.distanceM, route.durationS, surge, 'economy')
          : null,
    };
  }

  /**
   * Route for a trip: a direct pickup→dropoff route when there are no stops
   * (keeps the provider's real polyline), otherwise the summed legs through
   * every waypoint (distance/duration are the totals; the polyline is a
   * multi-segment line through the waypoints).
   */
  private routeFor(
    pickup: LatLng,
    dropoff: LatLng,
    stops?: StopDto[],
  ): Promise<RouteResult> {
    return routeThrough(this.geo, [
      pickup,
      ...(stops ?? []).map((s) => ({ lat: s.lat, lng: s.lng })),
      dropoff,
    ]);
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
    if (
      (dto.paymentMode ?? 'card') === 'card' &&
      !(await this.payments.canChargeCard(riderId, paymentMethodId))
    ) {
      throw new BadRequestException({
        code: 'PAYMENT_METHOD_REQUIRED',
        message: 'Add a card, or choose cash, to book this ride.',
      });
    }
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
    // Price lock: the rider agreed to a specific number on the estimate
    // screen. If the live price has moved past tolerance (or surge changed at
    // all), refuse with the fresh numbers so the app re-confirms — the audit
    // caught a rider quoted 1.0x and charged 2.0x because the fare was simply
    // recomputed here. Within tolerance, the quote itself is what we store.
    this.assertPriceLock(dto, est, surge);
    const grossFare = dto.quotedFare ?? est.fare;
    const lockedSurge = dto.quotedSurge ?? surge;

    const initialStatus = scheduledAt
      ? TripStatus.scheduled
      : TripStatus.requested;

    const passenger = TripsService.resolvePassenger(dto);

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
        pickupNote: dto.pickupNote?.trim() || undefined,
        passengerName: passenger?.name,
        passengerPhone: passenger?.phone,
        routePolyline: route.polyline,
        stops: dto.stops && dto.stops.length > 0 ? (dto.stops as object[]) : undefined,
        distanceM: route.distanceM,
        durationS: route.durationS,
        fareEstimate: grossFare,
        surgeMultiplier: lockedSurge,
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
        grossFare,
        riderId,
        trip.id,
      );
      if (discount > 0) {
        trip = await this.prisma.trip.update({
          where: { id: trip.id },
          data: {
            promoCode: dto.promoCode.trim().toUpperCase(),
            promoDiscount: discount,
            fareEstimate: Math.max(grossFare - discount, 0),
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
    // riders in the same area until it decays). Keyed by rider so retries
    // can't stack.
    await this.surge.recordDemand(dto.pickupLat, dto.pickupLng, riderId);

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
   * Compares the rider's quoted fare/surge with the live recomputation. A
   * mismatch is a 409 whose body carries the fresh numbers:
   *   { code: 'PRICE_CHANGED', fare, surge, estimate: { fare, surge, tier } }
   * No quote supplied (older clients) → nothing to compare, live price applies.
   */
  private assertPriceLock(
    dto: CreateTripDto,
    est: { fare: number; breakdown: unknown },
    surge: number,
  ): void {
    const fare = est.fare;
    if (dto.quotedFare === undefined && dto.quotedSurge === undefined) return;
    const surgeChanged =
      dto.quotedSurge !== undefined && Math.abs(dto.quotedSurge - surge) > 1e-9;
    let fareChanged = false;
    if (dto.quotedFare !== undefined) {
      const base = Math.max(dto.quotedFare, 0.01);
      fareChanged = Math.abs(fare - dto.quotedFare) / base > PRICE_LOCK_TOLERANCE;
    }
    // A surge tick that leaves the fare where it was is not a price change;
    // bouncing the rider for it read as "Price updated to $6.50" (unchanged).
    if (!fareChanged) return;
    throw new ConflictException({
      statusCode: 409,
      code: 'PRICE_CHANGED',
      message: surgeChanged
        ? `The price has changed (now ${surge}x). Please confirm the new fare.`
        : 'The price has changed. Please confirm the new fare.',
      fare,
      surge,
      // Carry the fresh itemisation too, so the app's "Details" list still
      // adds up to the number it is now asking the rider to confirm.
      estimate: {
        tier: dto.tier,
        fare,
        surge,
        currency: CURRENCY,
        breakdown: est.breakdown,
      },
    });
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
    // Arrival geofence: "arrived" starts the rider's no-show clock and the
    // cancellation-fee window, so a driver must actually be at the pickup.
    // Checked against their last *fresh* GPS fix; with no fix (or a stale
    // one) the tap is allowed — we never block on data we don't have.
    const arrivedDistanceM = await this.assertNearPickup(driverId, trip);
    await this.stateMachine.transition({
      tripId,
      from: TripStatus.accepted,
      to: TripStatus.arrived,
      actor: 'driver',
      data: { arrivedAt: new Date() },
      meta: { arrivedDistanceM: arrivedDistanceM ?? null },
    });
    this.realtime.emitToUser(trip.riderId, 'trip:arrived', { tripId });
    void this.notifications.notifyTrip(trip.riderId, 'arrived', { tripId });
    // The booker gets the push above; the passenger is standing at the kerb
    // and may have no app at all, so they get a text.
    this.notifyPassenger(trip, `Your ${BRAND_NAME} ride is here at the pickup point.`);
    return { status: TripStatus.arrived, arrivedDistanceM: arrivedDistanceM ?? null };
  }

  /**
   * Distance (m) from the driver's last fresh fix to the pickup, or null if
   * unknown/stale. Throws 400 when the fix is fresh and outside
   * ARRIVAL_RADIUS_M.
   */
  /** Who is actually travelling, when the booker is not.
   *
   *  A phone is required because everything the passenger needs depends on it:
   *  the driver calls them, and the start code is texted to them. A name on its
   *  own would leave the driver looking for somebody they cannot reach, so it
   *  is refused rather than silently dropped. A phone with no name is fine —
   *  the driver still has someone to call.
   */
  static resolvePassenger(dto: {
    passengerName?: string;
    passengerPhone?: string;
  }): { name: string | null; phone: string } | null {
    const name = dto.passengerName?.trim() || null;
    const phone = dto.passengerPhone?.trim() || null;
    if (!name && !phone) return null; // ordinary ride: the booker travels
    if (!phone) {
      throw new BadRequestException(
        'A passenger phone number is required when booking for someone else.',
      );
    }
    return { name, phone };
  }

  private async assertNearPickup(
    driverId: string,
    trip: Trip,
  ): Promise<number | null> {
    const loc = await this.redis.client.hgetall(RedisKeys.driverLoc(driverId));
    const lat = Number(loc?.lat);
    const lng = Number(loc?.lng);
    const ts = Number(loc?.ts);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
    if (!Number.isFinite(ts) || Date.now() - ts > ARRIVAL_FIX_MAX_AGE_MS) return null;
    const distanceM = Math.round(
      haversineMeters({ lat, lng }, { lat: trip.pickupLat, lng: trip.pickupLng }),
    );
    const radius = this.config.get<number>('arrivalRadiusM') ?? 150;
    if (distanceM > radius) {
      throw new BadRequestException(
        `You're still ${distanceM} m from the pickup`,
      );
    }
    return distanceM;
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
    // Navigation context for the on-trip leg so every GPS ping can carry a
    // cheap ETA/remaining-distance to the rider (LocationService reads this).
    await this.redis.client.hset(RedisKeys.tripNav(tripId), {
      phase: 'trip',
      targetLat: trip.dropoffLat,
      targetLng: trip.dropoffLng,
      // Stops still ahead, in order: re-routes go through them and each is
      // dropped once the car reaches it (LocationService).
      waypoints: JSON.stringify(
        ((trip.stops as unknown as StopDto[] | null) ?? []).map((s) => ({
          lat: s.lat,
          lng: s.lng,
        })),
      ),
      polyline: trip.routePolyline ?? '',
      avgSpeedMps:
        trip.distanceM && trip.durationS && trip.durationS > 0
          ? trip.distanceM / trip.durationS
          : '',
    });
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

  /**
   * POST /trips/:id/end-early — either party ends an in-progress ride where
   * the car is now. Settles like the driver's explicit early end: metered on
   * what was driven, floored at the tier minimum (never the estimate), and
   * both apps get the usual `trip:completed` receipt.
   */
  async endTripEarly(userId: string, tripId: string, reason?: string) {
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) throw new NotFoundException('Trip not found');
    const byRider = trip.riderId === userId;
    if (!byRider && trip.driverId !== userId) {
      throw new ForbiddenException('Not your trip');
    }
    if (trip.status !== TripStatus.in_progress || !trip.driverId) {
      throw new BadRequestException({
        code: 'TRIP_NOT_IN_PROGRESS',
        message: 'Only a ride that has started can be ended early.',
      });
    }
    const why =
      reason?.trim() || (byRider ? 'Rider ended the trip' : 'Driver ended the trip');
    return this.completeTrip(trip.driverId, tripId, {
      endEarly: true,
      reason: why,
      endedBy: byRider ? 'rider' : 'driver',
    });
  }

  /** Metres from the driver's last FRESH fix to the drop-off; null when there
   *  is no fix or it is too old to trust (the guard is then skipped). */
  private async driverDistanceToDropoff(
    driverId: string,
    trip: Trip,
  ): Promise<number | null> {
    const loc = await this.redis.client.hgetall(RedisKeys.driverLoc(driverId));
    const lat = Number(loc?.lat);
    const lng = Number(loc?.lng);
    const ts = Number(loc?.ts);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
    if (!Number.isFinite(ts) || Date.now() - ts > ARRIVAL_FIX_MAX_AGE_MS) return null;
    return Math.round(
      haversineMeters({ lat, lng }, { lat: trip.dropoffLat, lng: trip.dropoffLng }),
    );
  }

  async completeTrip(
    driverId: string,
    tripId: string,
    opts: { endEarly?: boolean; reason?: string; endedBy?: 'driver' | 'rider' } = {},
  ) {
    const trip = await this.assertDriverTrip(
      driverId,
      tripId,
      TripStatus.in_progress,
    );
    // Complete ALWAYS ends the trip where the driver is (owner rule). What it
    // must never do is what the audit caught: a 0 m / 11 s trip completed at
    // the pickup charged 100% of the estimate. So: a trip that ended away from
    // the drop-off, or with no evidence it got there and barely any distance
    // driven, is charged as a short trip — metered on what was actually
    // driven, floored at the tier minimum, never lifted to the estimate.
    const toDropoffM = await this.driverDistanceToDropoff(driverId, trip);
    const drivenNow = Number(
      (await this.redis.client.get(RedisKeys.tripDriven(tripId))) ?? 0,
    );
    const driven = Number.isFinite(drivenNow) ? drivenNow : 0;
    const radius = this.config.get<number>('completeDropoffRadiusM') ?? 500;
    const minDriven = this.config.get<number>('completeMinDrivenM') ?? 200;
    const farFromDropoff = toDropoffM !== null && toDropoffM > radius;
    const unknownAndShort = toDropoffM === null && driven < minDriven;
    const endEarly = opts.endEarly === true;
    const early = endEarly || farFromDropoff || unknownAndShort;
    const { fareFinal, distanceM, durationS, breakdown } =
      await this.settleFare(trip, {
        early,
        endedEarly: endEarly || farFromDropoff,
        reason: endEarly ? opts.reason?.trim() : undefined,
        endedAwayFromDropoffM: farFromDropoff ? toDropoffM : undefined,
      });
    if (early) {
      this.logger.log(
        `trip ${tripId} ended ${endEarly ? `early by ${opts.endedBy ?? 'driver'}` : 'short of the drop-off'} ` +
          `(${toDropoffM ?? '?'} m from drop-off, ${Math.round(driven)} m driven` +
          `${opts.reason ? `, reason: ${opts.reason}` : ''}); fare ${fareFinal} (${breakdown.fareBasis})`,
      );
    }
    await this.stateMachine.transition({
      tripId,
      from: TripStatus.in_progress,
      to: TripStatus.completed,
      actor: opts.endedBy ?? 'driver',
      data: { completedAt: new Date(), fareFinal, distanceM, durationS },
      // The itemised fare is persisted on the completion event (no trip
      // column for it) so GET /payments/:tripId/receipt can replay it.
      meta: { breakdown: { ...breakdown } },
    });

    // Release the driver back to the available pool.
    await this.redis.client.set(RedisKeys.driverStatus(driverId), 'online');
    await this.redis.client.del(
      RedisKeys.driverActiveTrip(driverId),
      RedisKeys.driverActiveRider(driverId),
      RedisKeys.tripNav(tripId),
      RedisKeys.tripWatch(tripId),
    );
    // ...and make them dispatchable NOW, at the drop-off, instead of on their
    // next GPS ping (see rejoinPool).
    await this.rejoinPool(driverId);
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
      breakdown,
    };
    this.realtime.emitToUser(trip.riderId, 'trip:completed', receipt);
    this.realtime.emitToUser(driverId, 'trip:completed', receipt);
    // Pay any quest this trip just finished (best-effort, never throws).
    void this.quests?.onTripCompleted(driverId, tripId);
    void this.notifications.notifyTrip(trip.riderId, 'completed', { tripId });
    void this.notifications.notifyTrip(
      driverId,
      'completed',
      {
        tripId,
        earned: (split.driverPayout ?? split.fareFinal).toFixed(2),
      },
      'driver',
    );
    // Best-effort emailed receipt (SES when keyed, mock otherwise). Never blocks
    // or fails the completion — EmailService swallows its own errors. When the
    // capture is still pending the processor sends it once the fare lands.
    if (paymentStatus === 'captured') {
      void (async () => {
        const rider = await this.prisma.user.findUnique({
          where: { id: trip.riderId },
          select: { email: true },
        });
        await this.email.sendReceipt(rider?.email, tripId, split.fareFinal, trip.currency);
      })();
    }
    return receipt;
  }

  /**
   * Determines the final fare at completion from the trip odometer (actual
   * driven meters accumulated by LocationService) and wall-clock duration.
   * Always clears the odometer keys.
   *
   * Rules (whole-currency rounding via roundFare throughout):
   *  - normal (at the drop-off, trail >= MIN_TRAIL_M): metered, clamped to
   *    [FARE_CLAMP_MIN, FARE_CLAMP_MAX] x the gross estimate, floored at the
   *    tier minimum;
   *  - normal with no usable trail (sparse GPS but the car IS at / can't be
   *    shown away from the drop-off): the up-front estimate;
   *  - early / short (driver ended early, or completed away from the
   *    drop-off): max(minimum fare, metered), capped at FARE_CLAMP_MAX x
   *    estimate — never lifted to the estimate.
   */
  private async settleFare(
    trip: Trip,
    opts: {
      early?: boolean;
      endedEarly?: boolean;
      reason?: string;
      endedAwayFromDropoffM?: number;
    } = {},
  ): Promise<{
    fareFinal: number;
    distanceM: number | null;
    durationS: number | null;
    breakdown: ReceiptBreakdown;
  }> {
    const drivenRaw = await this.redis.client.get(RedisKeys.tripDriven(trip.id));
    await this.redis.client.del(
      RedisKeys.tripDriven(trip.id),
      RedisKeys.tripMeterLast(trip.id),
    );
    const estimate = trip.fareEstimate ? Number(trip.fareEstimate) : 0;
    const drivenNum = drivenRaw ? Number(drivenRaw) : 0;
    const driven = Number.isFinite(drivenNum) ? drivenNum : 0;
    const surge = trip.surgeMultiplier ? Number(trip.surgeMultiplier) : 1;
    const discount = trip.promoDiscount ? Number(trip.promoDiscount) : 0;
    const currency = trip.currency ?? CURRENCY;
    const early = opts.early === true;
    const meta = {
      endedEarly: opts.endedEarly === true,
      endReason: opts.reason,
      endedAwayFromDropoffM: opts.endedAwayFromDropoffM,
    };

    // Need a meaningful trail (>= 50 m) to trust the odometer over the estimate
    // — but only for a trip that plausibly reached the drop-off.
    if (!early && driven < MIN_TRAIL_M) {
      // The estimate is only a usable answer if there actually is one. A trip
      // whose `fareEstimate` is missing or zero used to settle at exactly
      // $0.00 here — a free ride for the rider, no earning for the driver, and
      // a receipt that reads as broken. Re-price the routed distance/time
      // instead; `estimateForTier` is floored at the tier's minimum fare, so
      // the worst case is the minimum rather than nothing.
      let fareFinal = estimate;
      if (!(fareFinal > 0)) {
        const repriced = this.pricing.estimateForTier(
          trip.tier,
          trip.distanceM ?? 0,
          trip.durationS ?? 0,
          surge,
        ).fare;
        fareFinal = Math.max(repriced - discount, 0);
        this.logger.warn(
          `trip ${trip.id} had no usable fare estimate (${String(
            trip.fareEstimate,
          )}) and no GPS trail; settled at the re-priced minimum ${fareFinal}`,
        );
      }
      return {
        fareFinal,
        distanceM: trip.distanceM,
        durationS: trip.durationS,
        breakdown: this.breakdownFor(
          trip.tier,
          trip.distanceM ?? 0,
          trip.durationS ?? 0,
          surge,
          discount,
          fareFinal,
          'estimate',
          meta,
        ),
      };
    }

    const distanceM = Math.round(driven);
    const durationS = trip.startedAt
      ? Math.max(1, Math.round((Date.now() - trip.startedAt.getTime()) / 1000))
      : trip.durationS;
    const metered = this.pricing.estimateForTier(
      trip.tier,
      distanceM,
      durationS ?? 0,
      surge,
    ).fare;
    // Carry the up-front promo discount onto the final (odometer-based) fare.
    // `fareEstimate` is stored net of the promo; the clamp is on gross fares.
    const grossEstimate = estimate + discount;
    const gross = early
      ? this.shortTripFare(metered, grossEstimate, trip.tier, currency)
      : this.clampFare(metered, grossEstimate, trip.tier, currency);
    const fareFinal = Math.max(gross - discount, 0);
    return {
      fareFinal,
      distanceM,
      durationS,
      breakdown: this.breakdownFor(
        trip.tier,
        distanceM,
        durationS ?? 0,
        surge,
        discount,
        fareFinal,
        null,
        meta,
      ),
    };
  }

  /**
   * Itemised components as pricing computes them, plus promo/tip slots, and
   * which rule produced the headline (`fareBasis`). The gap between the raw
   * metered parts and the charged gross is reported as a minimum-fare top-up
   * ONLY when the minimum is what applied; any other move (the estimate
   * clamp, the up-front fallback) is `fareAdjustment`, so a receipt never
   * calls an estimate bound a "minimum fare".
   */
  private breakdownFor(
    tier: string,
    distanceM: number,
    durationS: number,
    surge: number,
    promoDiscount: number,
    fareFinal: number,
    forcedBasis: FareBasis | null,
    meta: { endedEarly: boolean; endReason?: string; endedAwayFromDropoffM?: number },
  ): ReceiptBreakdown {
    const b = this.pricing.estimateForTier(tier, distanceM, durationS, surge).breakdown;
    const itemised = b.baseFare + b.distanceFare + b.timeFare + b.bookingFee;
    const gross = fareFinal + promoDiscount;
    const gap = Math.round((gross - itemised) * 100) / 100;
    const minFare = this.pricing.minFareFor(tier);
    let basis: FareBasis;
    if (forcedBasis) basis = forcedBasis;
    // Within rounding of the metered parts: metered.
    else if (Math.abs(gap) < 1) basis = 'metered';
    // Lifted exactly to the tier minimum (and the metered parts were below it).
    else if (gap > 0 && Math.abs(gross - minFare) < 1) basis = 'minimum';
    else basis = 'estimate';
    const round2 = (n: number) => Math.round(n * 100) / 100;
    return {
      ...b,
      promoDiscount: round2(promoDiscount),
      tip: 0,
      minimumFareAdjustment: basis === 'minimum' && gap > 0 ? gap : 0,
      fareAdjustment: basis === 'minimum' || Math.abs(gap) < 0.005 ? 0 : gap,
      fareBasis: basis,
      endedEarly: meta.endedEarly,
      ...(meta.endReason ? { endReason: meta.endReason } : {}),
      ...(meta.endedAwayFromDropoffM !== undefined
        ? { endedAwayFromDropoffM: meta.endedAwayFromDropoffM }
        : {}),
    };
  }

  /**
   * Bound a metered (GPS-derived, driver-supplied) gross fare to
   * [FARE_CLAMP_MIN, FARE_CLAMP_MAX] × the gross up-front estimate, then floor
   * at the tier's minimum fare. Without a usable estimate the metered fare is
   * only floored. Only for trips that plausibly reached the drop-off.
   */
  private clampFare(
    metered: number,
    grossEstimate: number,
    tier: string,
    currency: string,
  ): number {
    let fare = metered;
    if (grossEstimate > 0) {
      fare = Math.min(
        Math.max(fare, grossEstimate * FARE_CLAMP_MIN),
        grossEstimate * FARE_CLAMP_MAX,
      );
    }
    fare = Math.max(fare, this.pricing.minFareFor(tier));
    // The charged fare follows the same rule as the quote: whole rupees.
    return roundFare(fare, currency);
  }

  /**
   * A trip that ended early / away from the drop-off: max(minimum fare,
   * metered). There is no lower clamp to the estimate (the rider did not get
   * the ride they were quoted); the upper FARE_CLAMP_MAX bound still protects
   * the rider from a spoofed odometer.
   */
  private shortTripFare(
    metered: number,
    grossEstimate: number,
    tier: string,
    currency: string,
  ): number {
    let fare = metered;
    if (grossEstimate > 0) fare = Math.min(fare, grossEstimate * FARE_CLAMP_MAX);
    fare = Math.max(fare, this.pricing.minFareFor(tier));
    return roundFare(fare, currency);
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
    return {
      ...this.serialize(trip, userId),
      ...(await this.driverSnapshot(trip)),
      ...(await this.riderSnapshot(trip, userId)),
    };
  }

  /**
   * `driver` + `vehicle` as the rider's card shows them (same shape as
   * `trip:accepted`), so a rider who relaunches mid-ride gets the name,
   * rating and plate back instead of "Your driver ★ —". Empty when no driver
   * is assigned yet.
   */
  private async driverSnapshot(trip: Trip) {
    if (!trip.driverId) return {};
    const driver = await this.prisma.user
      .findUnique({
        where: { id: trip.driverId },
        include: { driverProfile: true },
      })
      .catch(() => null);
    if (!driver) return {};
    // Last known position, so a rider restoring the screen (cold start, or
    // back from a suspend) sees the car where it actually is instead of where
    // it was when the app went away. Live movement still arrives over
    // `trip:driver_location`; this only seeds the first frame. Never fatal —
    // a missing or unreadable fix just means no marker until the next ping.
    let driverLocation: { lat: number; lng: number; heading: number; ts: number } | null =
      null;
    try {
      const loc = await this.redis.client.hgetall(
        RedisKeys.driverLoc(trip.driverId),
      );
      const lat = Number(loc?.lat);
      const lng = Number(loc?.lng);
      if (Number.isFinite(lat) && Number.isFinite(lng)) {
        driverLocation = {
          lat,
          lng,
          heading: Number(loc?.heading) || 0,
          ts: Number(loc?.ts) || 0,
        };
      }
    } catch {
      // ignore — the snapshot is best-effort
    }

    return {
      driver: {
        id: driver.id,
        name: driver.fullName ?? 'Your driver',
        rating: Number(driver.ratingAvg ?? 5),
        // Only while the ride is live — history never re-exposes a number.
        // PILOT ONLY: the driver's real number; production must use a
        // masked/proxy number instead.
        phone: CONTACTABLE.includes(trip.status) ? driver.phone : undefined,
      },
      vehicle: {
        make: driver.driverProfile?.vehicleMake,
        model: driver.driverProfile?.vehicleModel,
        color: driver.driverProfile?.vehicleColor,
        plate: driver.driverProfile?.plateNumber,
      },
      driverLocation,
    };
  }

  /**
   * The rider as the assigned driver needs them: name + phone for the "Call
   * rider" button on the en-route / arrived / on-trip screens. Only for the
   * driver of this trip and only while it is live (accepted → in progress);
   * the rider never gets this block and a finished trip never re-exposes it.
   * PILOT ONLY: this is the rider's real number (users.phone). Production
   * must hand out a masked/proxy number instead.
   */
  private async riderSnapshot(trip: Trip, viewerId: string) {
    if (!trip.driverId || viewerId !== trip.driverId) return {};
    if (!CONTACTABLE.includes(trip.status)) return {};
    const rider = await this.prisma.user
      .findUnique({
        where: { id: trip.riderId },
        select: { id: true, fullName: true, phone: true },
      })
      .catch(() => null);
    if (!rider) return {};
    return {
      rider: { id: rider.id, name: rider.fullName ?? 'Rider', phone: rider.phone },
    };
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
    if (!trip) return null;
    return {
      ...this.serialize(trip, userId),
      ...(await this.driverSnapshot(trip)),
      ...(await this.riderSnapshot(trip, userId)),
    };
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
      void this.notifications.notifyTrip(
        trip.driverId,
        'cancelled',
        { tripId },
        'driver',
      );
      await this.releaseDriver(trip.driverId);
    }
    await this.releasePromo(trip);
    await this.releaseDemand(trip);

    let fee = 0;
    // No fee when the ride was blocked on the driver's side (start code
    // locked after repeated wrong entries): the rider isn't walking away
    // from a ride they could have taken.
    if (feeApplies && !(await this.otpLocked(tripId))) {
      const configured = this.config.get<number>('cancellationFee') ?? 5;
      const estimate = Number(trip.fareEstimate ?? 0);
      // A cancellation must never cost more than the ride would have.
      const amount = estimate > 0 ? Math.min(configured, estimate) : configured;
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
  async driverCancelTrip(
    driverId: string,
    tripId: string,
    reason: string,
    noShow = false,
  ) {
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
    if (noShow) {
      // A no-show is only a no-show once the driver has been AT the pickup
      // for the full wait — the clock is the server's arrival stamp, never
      // the app's, so a driver can't charge a rider who is still walking out.
      if (trip.status !== TripStatus.arrived || !trip.arrivedAt) {
        throw new BadRequestException({
          code: 'NO_SHOW_NOT_ARRIVED',
          message: 'Mark yourself arrived at the pickup first.',
        });
      }
      const waitedSec = (Date.now() - trip.arrivedAt.getTime()) / 1000;
      if (waitedSec < NO_SHOW_WAIT_SEC) {
        throw new BadRequestException({
          code: 'NO_SHOW_TOO_EARLY',
          message: 'Please wait for the rider a little longer.',
          secondsLeft: Math.ceil(NO_SHOW_WAIT_SEC - waitedSec),
        });
      }
    }

    await this.stateMachine.transition({
      tripId,
      from: trip.status,
      to: TripStatus.cancelled,
      actor: 'driver',
      data: { cancelReason: trimmed, cancelledBy: 'driver' },
      meta: { reason: trimmed, driverId },
    });
    // Durable record for the driver's cancellation rate; a rider no-show is
    // recorded apart so it never counts against the driver.
    void recordOfferEvent(
      this.prisma,
      driverId,
      tripId,
      noShow ? 'cancelled_no_show' : 'cancelled',
    );

    await this.releaseDriver(driverId);
    await this.releasePromo(trip);
    await this.releaseDemand(trip);

    // No-show: the rider pays the same fee a late rider cancel costs (never
    // more than the ride would have), and the driver gets their share of it.
    // Not when the start code is locked — the ride was blocked on the
    // driver's side, so the rider isn't the one who walked away.
    let fee = 0;
    if (noShow && !(await this.otpLocked(tripId))) {
      const configured = this.config.get<number>('cancellationFee') ?? 5;
      const estimate = Number(trip.fareEstimate ?? 0);
      const amount = estimate > 0 ? Math.min(configured, estimate) : configured;
      try {
        fee = await this.payments.chargeCancellationFee(tripId, amount);
      } catch {
        this.realtime.emitToUser(trip.riderId, 'trip:payment_warning', {
          tripId,
          message: 'Payment could not be processed',
        });
      }
    }

    this.realtime.emitToUser(trip.riderId, 'trip:cancelled', {
      tripId,
      by: 'driver',
      reason: trimmed,
      noShow,
      fee,
    });
    void this.notifications.notifyTrip(trip.riderId, 'cancelled', { tripId });
    this.realtime.emitToUser(driverId, 'trip:cancelled', {
      tripId,
      by: 'driver',
      reason: trimmed,
      noShow,
      fee,
    });

    return { status: TripStatus.cancelled, fee };
  }

  /** Whether a rider cancel is charged: driver committed AND grace elapsed. */
  private async otpLocked(tripId: string): Promise<boolean> {
    try {
      return (await this.redis.client.exists(otpLockKey(tripId))) > 0;
    } catch {
      return false;
    }
  }

  private minFareOrNull(tier: string): number | null {
    try {
      const m = this.pricing.minFareFor(tier);
      return Number.isFinite(m) ? m : null;
    } catch {
      return null;
    }
  }

  private cancellationFeeApplies(trip: Trip): boolean {
    const committed =
      trip.status === TripStatus.accepted || trip.status === TripStatus.arrived;
    if (!committed) return false;
    if (!trip.acceptedAt) return false;
    return Date.now() - trip.acceptedAt.getTime() >= CANCEL_GRACE_MS;
  }

  /** Return a driver to the available pool (clears their active-trip keys). */
  private async releaseDriver(driverId: string): Promise<void> {
    const tripId = await this.redis.client.get(RedisKeys.driverActiveTrip(driverId));
    await this.redis.client.set(RedisKeys.driverStatus(driverId), 'online');
    await this.redis.client.del(
      RedisKeys.driverActiveTrip(driverId),
      RedisKeys.driverActiveRider(driverId),
      ...(tripId ? [RedisKeys.tripNav(tripId), RedisKeys.tripWatch(tripId)] : []),
    );
    await this.rejoinPool(driverId);
  }

  /**
   * Put a just-freed driver straight back into their tier's dispatch GEO pool
   * at their last known position. Dispatch removes a driver from the pool at
   * assignment and LocationService only re-adds on the next `driver:location`
   * ping — so a rider booking right after a drop-off could find "no drivers"
   * (or a far-away one) while the nearest driver sat on the rate-rider screen.
   * Only a FRESH fix (within PRESENCE_STALE_MS) is used: a stale one would be
   * evicted by dispatch anyway, and the next ping adds them normally.
   * Best-effort — never fails the completion/cancel that called it.
   */
  private async rejoinPool(driverId: string): Promise<void> {
    try {
      const [tier, loc] = await Promise.all([
        this.redis.client.get(RedisKeys.driverTier(driverId)),
        this.redis.client.hgetall(RedisKeys.driverLoc(driverId)),
      ]);
      const lat = Number(loc?.lat);
      const lng = Number(loc?.lng);
      const ts = Number(loc?.ts);
      if (!tier || !Number.isFinite(lat) || !Number.isFinite(lng) || !loc?.lat) {
        return;
      }
      if (!Number.isFinite(ts) || Date.now() - ts > PRESENCE_STALE_MS) return;
      const added = await this.redis.client.geoadd(RedisKeys.driversGeo(tier), lng, lat, driverId);
      // Wake any ride search of this tier waiting for a free driver.
      if (Number(added) > 0) await this.redis.client.incr(RedisKeys.dispatchPoolGen(tier));
    } catch (e) {
      this.logger.warn(`could not return driver ${driverId} to the pool: ${String(e)}`);
    }
  }

  /** A request that ended without a ride no longer counts as local demand. */
  private async releaseDemand(trip: Trip): Promise<void> {
    try {
      await this.surge.releaseDemand(trip.pickupLat, trip.pickupLng, trip.riderId);
    } catch (e) {
      this.logger.warn(`demand release failed for trip ${trip.id}: ${String(e)}`);
    }
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

  /**
   * The caller's last 50 trips, newest first. Each row carries `myRating`
   * (the caller's own stars for that trip, null if unrated) and — on the
   * rider's rows only — a `driver` block with name, photo and vehicle so the
   * app can say "Rate your ride with Aziz" without another lookup; the
   * driver's rows carry `rider.name` (first name only). History never
   * carries a phone number. One query: the driver and the caller's
   * rating are joined in, not fetched per trip.
   */
  async history(userId: string) {
    const trips = await this.prisma.trip.findMany({
      where: { OR: [{ riderId: userId }, { driverId: userId }] },
      orderBy: { requestedAt: 'desc' },
      take: 50,
      include: {
        driver: {
          select: {
            fullName: true,
            photoUrl: true,
            driverProfile: {
              select: {
                vehicleMake: true,
                vehicleModel: true,
                vehicleColor: true,
                plateNumber: true,
              },
            },
          },
        },
        // The driver's own rows name who they drove — the first name only,
        // never a phone number.
        rider: { select: { fullName: true } },
        ratings: { where: { fromUser: userId }, select: { stars: true } },
      },
    });
    return trips.map((t) => {
      const { driver, rider, ratings, ...trip } = t;
      const riderFirst = rider?.fullName?.trim().split(/\s+/)[0];
      return {
        ...this.serialize(trip, userId),
        ...(t.riderId === userId && driver
          ? { driver: TripsService.historyDriver(driver) }
          : {}),
        ...(t.driverId === userId && t.riderId !== userId && riderFirst
          ? { rider: { name: riderFirst } }
          : {}),
        myRating: ratings[0]?.stars ?? null,
      };
    });
  }

  /** The driver as a history row shows them: no phone, no id. */
  static historyDriver(d: {
    fullName: string | null;
    photoUrl: string | null;
    driverProfile: {
      vehicleMake: string | null;
      vehicleModel: string | null;
      vehicleColor: string | null;
      plateNumber: string | null;
    } | null;
  }) {
    const p = d.driverProfile;
    const label = [p?.vehicleColor, p?.vehicleMake, p?.vehicleModel]
      .map((s) => s?.trim())
      .filter((s) => !!s)
      .join(' ');
    return {
      name: d.fullName?.trim() || 'Your driver',
      avatarUrl: d.photoUrl ?? null,
      vehicleLabel: label || null,
      plate: p?.plateNumber ?? null,
    };
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
      pickupNote: t.pickupNote,
      // Who is travelling, when that is not the booker. Both sides see it: the
      // booker so their screen says who the ride is for, the driver so they
      // collect and call the right person. Null on an ordinary ride.
      passenger: t.passengerPhone
        ? { name: t.passengerName, phone: t.passengerPhone }
        : null,
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
      // What a late cancel costs, so the app can state the amount up front.
      cancellationFee: this.config.get<number>('cancellationFee') ?? 5,
      // How long the driver waits at the pickup before a no-show cancel.
      noShowWaitSec: NO_SHOW_WAIT_SEC,
      // The floor an early end is charged at, so "End trip here" can say it.
      minFare: this.minFareOrNull(t.tier),
      requestedAt: t.requestedAt,
      acceptedAt: t.acceptedAt,
      arrivedAt: t.arrivedAt,
      startedAt: t.startedAt,
      completedAt: t.completedAt,
    };
  }
}
