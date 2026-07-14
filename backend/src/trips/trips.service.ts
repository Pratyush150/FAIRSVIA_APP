import {
  BadRequestException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { RideTier, Trip, TripStatus } from '@prisma/client';
import { randomInt } from 'node:crypto';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { GEO_PROVIDER, GeoProvider, LatLng } from '../geo/geo-provider.interface';
import { CURRENCY } from '../pricing/fare-config';
import { PricingService } from '../pricing/pricing.service';
import { SurgeService } from '../surge/surge.service';
import { PromoService } from '../promo/promo.service';
import { RealtimeService } from '../realtime/realtime.service';
import { DispatchService } from '../dispatch/dispatch.service';
import { PaymentsService } from '../payments/payments.service';
import { NotificationsService } from '../notifications/notifications.service';
import { CreateTripDto } from './dto/create-trip.dto';
import { EstimateDto } from './dto/estimate.dto';
import { TripStateMachine } from './trip-state-machine';

const CANCELLABLE: TripStatus[] = [
  TripStatus.requested,
  TripStatus.matching,
  TripStatus.accepted,
  TripStatus.arrived,
];

@Injectable()
export class TripsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly pricing: PricingService,
    private readonly surge: SurgeService,
    private readonly promo: PromoService,
    private readonly stateMachine: TripStateMachine,
    private readonly redis: RedisService,
    private readonly realtime: RealtimeService,
    private readonly dispatch: DispatchService,
    private readonly payments: PaymentsService,
    private readonly notifications: NotificationsService,
    private readonly config: ConfigService,
    @Inject(GEO_PROVIDER) private readonly geo: GeoProvider,
  ) {}

  /** Route + fare estimate for every tier (what the rider picks from). */
  async estimate(dto: EstimateDto) {
    const pickup: LatLng = { lat: dto.pickupLat, lng: dto.pickupLng };
    const dropoff: LatLng = { lat: dto.dropoffLat, lng: dto.dropoffLng };
    const route = await this.geo.route(pickup, dropoff);
    const surge = await this.surge.multiplierFor(pickup.lat, pickup.lng);
    return {
      distanceM: route.distanceM,
      durationS: route.durationS,
      polyline: route.polyline,
      surge,
      currency: CURRENCY,
      pickup,
      dropoff,
      tiers: this.pricing.estimateAllTiers(route.distanceM, route.durationS, surge),
    };
  }

  /** Create a trip in REQUESTED. Dispatch/matching arrives in Phase 2. */
  async createTrip(riderId: string, dto: CreateTripDto) {
    const pickup: LatLng = { lat: dto.pickupLat, lng: dto.pickupLng };
    const dropoff: LatLng = { lat: dto.dropoffLat, lng: dto.dropoffLng };
    const route = await this.geo.route(pickup, dropoff);
    const surge = await this.surge.multiplierFor(pickup.lat, pickup.lng);
    const est = this.pricing.estimateForTier(
      dto.tier,
      route.distanceM,
      route.durationS,
      surge,
    );

    let trip = await this.prisma.trip.create({
      data: {
        riderId,
        status: TripStatus.requested,
        tier: dto.tier as RideTier,
        pickupAddr: dto.pickupAddr,
        pickupLat: dto.pickupLat,
        pickupLng: dto.pickupLng,
        dropoffAddr: dto.dropoffAddr,
        dropoffLat: dto.dropoffLat,
        dropoffLng: dto.dropoffLng,
        routePolyline: route.polyline,
        distanceM: route.distanceM,
        durationS: route.durationS,
        fareEstimate: est.fare,
        surgeMultiplier: surge,
        currency: CURRENCY,
        startOtp: this.generateOtp(),
        paymentMode: dto.paymentMode ?? 'card',
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

    // This request now contributes to local demand (raising surge for the next
    // riders in the same area until it decays).
    await this.surge.recordDemand(dto.pickupLat, dto.pickupLng);

    // Initial audit event (creation: null -> requested).
    await this.prisma.tripEvent.create({
      data: {
        tripId: trip.id,
        fromStatus: null,
        toStatus: TripStatus.requested,
        actor: 'rider',
        meta: { tier: dto.tier },
      },
    });

    // Kick off matching without blocking the response (rider sees REQUESTED,
    // then MATCHING/ACCEPTED arrive over the socket).
    void this.dispatch
      .dispatchTrip(trip.id)
      .catch(() => undefined);

    return this.serialize(trip);
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
    if (trip.startOtp !== otp) {
      throw new BadRequestException('Incorrect start code');
    }
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
      });
    }
    // Auth-hold the estimated fare when the ride starts (manual capture).
    await this.payments.authorizeForTrip(tripId).catch((e) =>
      // Don't block the ride on a payment hiccup; capture will retry on complete.
      this.realtime.emitToUser(trip.riderId, 'trip:payment_warning', {
        tripId,
        message: String(e),
      }),
    );
    this.realtime.emitToUser(trip.riderId, 'trip:started', { tripId });
    void this.notifications.notifyTrip(trip.riderId, 'started', { tripId });
    return { status: TripStatus.in_progress };
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

    // Capture the fare and compute the platform-fee / driver-payout split.
    let split = {
      fareFinal: Number(fareFinal),
      platformFee: 0,
      driverPayout: Number(fareFinal),
    };
    try {
      split = await this.payments.captureForTrip(tripId);
    } catch (e) {
      this.realtime.emitToUser(trip.riderId, 'trip:payment_warning', {
        tripId,
        message: String(e),
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
    };
    this.realtime.emitToUser(trip.riderId, 'trip:completed', receipt);
    this.realtime.emitToUser(driverId, 'trip:completed', receipt);
    void this.notifications.notifyTrip(trip.riderId, 'completed', { tripId });
    void this.notifications.notifyTrip(driverId, 'completed', { tripId });
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
    const gross = this.pricing.estimateForTier(
      trip.tier,
      distanceM,
      durationS ?? 0,
      surge,
    ).fare;
    // Carry the up-front promo discount onto the final (odometer-based) fare.
    const discount = trip.promoDiscount ? Number(trip.promoDiscount) : 0;
    const fareFinal = Math.max(gross - discount, 0);
    return { fareFinal, distanceM, durationS };
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
    // late cancel wastes the driver's trip to the pickup.
    const feeApplies =
      trip.status === TripStatus.accepted || trip.status === TripStatus.arrived;

    // If a driver was already assigned, notify them and return them to the pool.
    if (trip.driverId) {
      this.realtime.emitToUser(trip.driverId, 'trip:cancelled', {
        tripId,
        by: 'rider',
        reason: reason ?? null,
      });
      void this.notifications.notifyTrip(trip.driverId, 'cancelled', { tripId });
      await this.redis.client.set(
        RedisKeys.driverStatus(trip.driverId),
        'online',
      );
      await this.redis.client.del(
        RedisKeys.driverActiveTrip(trip.driverId),
        RedisKeys.driverActiveRider(trip.driverId),
      );
    }

    let fee = 0;
    if (feeApplies) {
      const amount = this.config.get<number>('cancellationFee') ?? 30;
      try {
        fee = await this.payments.chargeCancellationFee(tripId, amount);
      } catch (e) {
        this.realtime.emitToUser(userId, 'trip:payment_warning', {
          tripId,
          message: String(e),
        });
      }
    }

    return { status: TripStatus.cancelled, fee };
  }

  async history(userId: string) {
    const trips = await this.prisma.trip.findMany({
      where: { OR: [{ riderId: userId }, { driverId: userId }] },
      orderBy: { requestedAt: 'desc' },
      take: 50,
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
      routePolyline: t.routePolyline,
      distanceM: t.distanceM,
      durationS: t.durationS,
      fareEstimate: t.fareEstimate ? Number(t.fareEstimate) : null,
      fareFinal: t.fareFinal ? Number(t.fareFinal) : null,
      promoCode: t.promoCode,
      promoDiscount: Number(t.promoDiscount),
      paymentMode: t.paymentMode,
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
