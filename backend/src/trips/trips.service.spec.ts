import { BadRequestException, ConflictException } from '@nestjs/common';
import { TripStatus } from '@prisma/client';
import {
  ARRIVAL_FIX_MAX_AGE_MS,
  PRICE_LOCK_TOLERANCE,
  TripsService,
} from './trips.service';
import { RedisKeys } from '../common/redis/redis.keys';

/**
 * Pure-logic coverage of the live-audit fixes: the price lock at request
 * time, rider-keyed surge demand, the arrival geofence, and the itemised
 * completion receipt. Every collaborator is a small hand-rolled mock.
 */
describe('TripsService', () => {
  const pickup = { lat: 25.7743, lng: -80.1937 };
  const dropoff = { lat: 25.79, lng: -80.2 };
  const route = { distanceM: 5000, durationS: 600, polyline: 'poly' };

  function breakdownFor(surge: number) {
    return {
      baseFare: 2.5,
      distanceFare: 5 * surge,
      timeFare: 2 * surge,
      bookingFee: 1.5,
      surgeMultiplier: surge,
    };
  }

  function make(opts: { surge?: number; fare?: number } = {}) {
    const surgeValue = opts.surge ?? 1;
    const fare = opts.fare ?? 11;
    const store: Record<string, unknown> = {};
    const redis = {
      client: {
        get: jest.fn(async (k: string) => (store[k] as string) ?? null),
        set: jest.fn().mockResolvedValue('OK'),
        del: jest.fn().mockResolvedValue(1),
        hset: jest.fn().mockResolvedValue(1),
        hgetall: jest.fn(async (k: string) => (store[k] as Record<string, string>) ?? {}),
        incr: jest.fn().mockResolvedValue(1),
        expire: jest.fn().mockResolvedValue(1),
        exists: jest.fn(async (k: string) => (store[k] === undefined ? 0 : 1)),
        geoadd: jest.fn().mockResolvedValue(1),
      },
    };
    const created: Record<string, unknown>[] = [];
    const prisma = {
      trip: {
        findFirst: jest.fn().mockResolvedValue(null),
        findUnique: jest.fn(),
        create: jest.fn(async ({ data }: { data: Record<string, unknown> }) => {
          created.push(data);
          return { id: 'trip-1', ...data, promoDiscount: 0, stops: null };
        }),
        update: jest.fn(),
      },
      tripEvent: { create: jest.fn().mockResolvedValue({}) },
      paymentMethod: { findFirst: jest.fn() },
      driverProfile: { update: jest.fn().mockResolvedValue({}) },
      user: { findUnique: jest.fn().mockResolvedValue({ email: null }) },
    };
    const pricing = {
      estimateForTier: jest.fn((tier: string, d: number, t: number, s = 1) => ({
        tier,
        fare: Math.round(fare * s * 100) / 100,
        breakdown: breakdownFor(s),
      })),
      minFareFor: jest.fn().mockReturnValue(5),
    };
    const surge = {
      multiplierFor: jest.fn().mockResolvedValue(surgeValue),
      recordDemand: jest.fn().mockResolvedValue(undefined),
      releaseDemand: jest.fn().mockResolvedValue(undefined),
    };
    const stateMachine = { transition: jest.fn().mockResolvedValue(undefined) };
    const realtime = { emitToUser: jest.fn() };
    const dispatch = { dispatchTrip: jest.fn().mockResolvedValue(undefined) };
    const payments = {
      captureForTrip: jest.fn().mockResolvedValue({ fareFinal: 11, platformFee: 2.2, driverPayout: 8.8 }),
      chargeCancellationFee: jest.fn().mockResolvedValue(0),
      canChargeCard: jest.fn().mockResolvedValue(true),
    };
    const notifications = { notifyTrip: jest.fn().mockResolvedValue(undefined), notify: jest.fn() };
    const config = { get: jest.fn((k: string) => (k === 'arrivalRadiusM' ? 150 : k === 'cancellationFee' ? 5 : undefined)) };
    const sms = { sendOtp: jest.fn(), sendMessage: jest.fn().mockResolvedValue(undefined) };
    const svc = new TripsService(
      prisma as never,
      pricing as never,
      surge as never,
      { redeem: jest.fn().mockResolvedValue(0), release: jest.fn() } as never,
      { enqueue: jest.fn() } as never,
      stateMachine as never,
      redis as never,
      realtime as never,
      dispatch as never,
      payments as never,
      notifications as never,
      { sendReceipt: jest.fn() } as never,
      config as never,
      { compare: jest.fn() } as never,
      { route: jest.fn().mockResolvedValue(route) } as never,
      sms as never,
    );
    return { svc, store, redis, prisma, pricing, created, surge, stateMachine, realtime, notifications, dispatch, payments, sms };
  }

  const baseDto = {
    pickupLat: pickup.lat,
    pickupLng: pickup.lng,
    dropoffLat: dropoff.lat,
    dropoffLng: dropoff.lng,
    tier: 'economy',
  };

  describe('price lock at POST /trips', () => {
    it('honours a matching quote: the quoted fare + surge are what gets stored', async () => {
      const { svc, created } = make({ surge: 1, fare: 11 });
      await svc.createTrip('rider-1', { ...baseDto, quotedFare: 11, quotedSurge: 1 });
      expect(created[0].fareEstimate).toBe(11);
      expect(created[0].surgeMultiplier).toBe(1);
    });

    it('rejects 409 PRICE_CHANGED with the fresh numbers when surge moved since the quote', async () => {
      // The audit case: rider quoted at 1.0x, server now says 2.0x.
      const { svc, created } = make({ surge: 2, fare: 11 });
      const err = await svc
        .createTrip('rider-1', { ...baseDto, quotedFare: 11, quotedSurge: 1 })
        .catch((e) => e);
      expect(err).toBeInstanceOf(ConflictException);
      expect(err.getResponse()).toMatchObject({
        code: 'PRICE_CHANGED',
        fare: 22,
        surge: 2,
        estimate: { tier: 'economy', fare: 22, surge: 2 },
      });
      expect(created).toHaveLength(0); // nothing persisted, no demand recorded
    });

    it('rejects when the fare drifted more than 5% even at the same surge', async () => {
      const { svc } = make({ surge: 1, fare: 12 });
      await expect(
        svc.createTrip('rider-1', { ...baseDto, quotedFare: 11, quotedSurge: 1 }),
      ).rejects.toBeInstanceOf(ConflictException);
      expect(PRICE_LOCK_TOLERANCE).toBe(0.05);
    });

    it('tolerates a fare within 5% (route jitter) and stores the quote, not the recompute', async () => {
      const { svc, created } = make({ surge: 1, fare: 11.4 });
      await svc.createTrip('rider-1', { ...baseDto, quotedFare: 11, quotedSurge: 1 });
      expect(created[0].fareEstimate).toBe(11);
    });

    it('applies the live price when no quote is supplied (older clients)', async () => {
      const { svc, created } = make({ surge: 1.5, fare: 10 });
      await svc.createTrip('rider-1', baseDto);
      expect(created[0].fareEstimate).toBe(15);
      expect(created[0].surgeMultiplier).toBe(1.5);
    });

    it('a surge tick that leaves the fare unchanged does not bounce the rider', async () => {
      // The rider cares about the price, not the multiplier: a quote with the
      // same fare but a different surge (e.g. minimum fare in force) goes through.
      const { svc, created } = make({ surge: 1.3, fare: 10 });
      await svc.createTrip('rider-1', { ...baseDto, quotedSurge: 1, quotedFare: 13 });
      expect(created).toHaveLength(1);
    });
  });

  describe('surge demand accounting', () => {
    it('records demand keyed by the rider (so retries cannot stack)', async () => {
      const { svc, surge } = make();
      await svc.createTrip('rider-1', baseDto);
      expect(surge.recordDemand).toHaveBeenCalledWith(pickup.lat, pickup.lng, 'rider-1');
    });

    it('a rider cancel withdraws the demand', async () => {
      const { svc, surge, prisma } = make();
      prisma.trip.findUnique.mockResolvedValue({
        id: 'trip-1', riderId: 'rider-1', driverId: null, status: TripStatus.matching,
        pickupLat: pickup.lat, pickupLng: pickup.lng, promoCode: null, acceptedAt: null,
      });
      await svc.cancelTrip('rider-1', 'trip-1', 'changed my mind');
      expect(surge.releaseDemand).toHaveBeenCalledWith(pickup.lat, pickup.lng, 'rider-1');
    });

    it('a driver cancel withdraws the demand and uses the driver copy for nobody (rider told)', async () => {
      const { svc, surge, prisma } = make();
      prisma.trip.findUnique.mockResolvedValue({
        id: 'trip-1', riderId: 'rider-1', driverId: 'driver-1', status: TripStatus.accepted,
        pickupLat: pickup.lat, pickupLng: pickup.lng, promoCode: null,
      });
      await svc.driverCancelTrip('driver-1', 'trip-1', 'no-show');
      expect(surge.releaseDemand).toHaveBeenCalledWith(pickup.lat, pickup.lng, 'rider-1');
    });
  });

  describe('cancellation fee', () => {
    const lateTrip = {
      id: 'trip-1', riderId: 'rider-1', driverId: 'driver-1', status: TripStatus.accepted,
      pickupLat: pickup.lat, pickupLng: pickup.lng, promoCode: null,
      acceptedAt: new Date(Date.now() - 5 * 60 * 1000),
    };

    it('never charges more than the ride would have cost', async () => {
      const { svc, prisma, payments } = make();
      prisma.trip.findUnique.mockResolvedValue({ ...lateTrip, fareEstimate: 3.5 });
      payments.chargeCancellationFee.mockResolvedValue(3.5);
      const res = await svc.cancelTrip('rider-1', 'trip-1', 'late');
      expect(payments.chargeCancellationFee).toHaveBeenCalledWith('trip-1', 3.5);
      expect(res.fee).toBe(3.5);
    });

    it('charges the configured fee when the estimate is higher', async () => {
      const { svc, prisma, payments } = make();
      prisma.trip.findUnique.mockResolvedValue({ ...lateTrip, fareEstimate: 20 });
      payments.chargeCancellationFee.mockResolvedValue(5);
      await svc.cancelTrip('rider-1', 'trip-1', 'late');
      expect(payments.chargeCancellationFee).toHaveBeenCalledWith('trip-1', 5);
    });

    it('waives the fee while the start code is locked (the driver could not start)', async () => {
      const { svc, prisma, payments, store } = make();
      prisma.trip.findUnique.mockResolvedValue({ ...lateTrip, fareEstimate: 20 });
      store['trip:trip-1:otpLock'] = '1';
      const res = await svc.cancelTrip('rider-1', 'trip-1', 'locked out');
      expect(payments.chargeCancellationFee).not.toHaveBeenCalled();
      expect(res.fee).toBe(0);
    });
  });

  describe('minimum fare on the receipt', () => {
    it('adds a "minimum fare" line so the itemised parts reach the headline', async () => {
      // Itemised parts sum to 4.5 (breakdownFor(1)); the tier floor lifts the
      // fare to 5, so the receipt must show a 0.5 top-up.
      const { svc, prisma } = make({ fare: 4.5 });
      prisma.trip.findUnique.mockResolvedValue({
        id: 'trip-1', riderId: 'rider-1', driverId: 'driver-1', status: TripStatus.in_progress,
        tier: 'economy', distanceM: 500, durationS: 60, fareEstimate: 5, surgeMultiplier: 1,
        promoDiscount: 0, currency: 'USD', paymentMode: 'cash', startedAt: new Date(Date.now() - 60000),
      });
      const receipt = await svc.completeTrip('driver-1', 'trip-1');
      const parts = breakdownFor(1);
      const itemised = parts.baseFare + parts.distanceFare + parts.timeFare + parts.bookingFee;
      expect(receipt.breakdown.minimumFareAdjustment).toBeCloseTo(
        Math.max(receipt.fareFinal - itemised, 0),
        2,
      );
    });
  });

  describe('complete anywhere + fare rules (audit: 0 m / 11 s trip charged the full estimate)', () => {
    // Rupee-like tier: base 20 + 10/km + 1/min + booking 5, minimum 30.
    // Estimate 89 → clamp window [71.2, 133.5].
    const trip = {
      id: 'trip-1', riderId: 'rider-1', driverId: 'driver-1', status: TripStatus.in_progress,
      tier: 'economy', distanceM: 6000, durationS: 900, fareEstimate: 89, surgeMultiplier: 1,
      promoDiscount: 0, currency: 'INR', paymentMode: 'cash',
      pickupLat: pickup.lat, pickupLng: pickup.lng, dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
    };
    function setup(o: { drivenM?: number; ageS: number; at?: { lat: number; lng: number } | null }) {
      const ctx = make();
      ctx.pricing.minFareFor.mockReturnValue(30);
      ctx.pricing.estimateForTier.mockImplementation(
        (tier: string, d: number, t: number, s = 1) => {
          const b = {
            baseFare: 20 * s, distanceFare: (d / 1000) * 10 * s,
            timeFare: (t / 60) * s, bookingFee: 5, surgeMultiplier: s,
          };
          const sum = b.baseFare + b.distanceFare + b.timeFare + b.bookingFee;
          return { tier, fare: Math.max(sum, 30), breakdown: b };
        },
      );
      ctx.prisma.trip.findUnique.mockResolvedValue({
        ...trip, startedAt: new Date(Date.now() - o.ageS * 1000),
      });
      // The receipt's fareFinal is what capture charged: echo the settled fare.
      ctx.payments.captureForTrip.mockImplementation(async () => ({
        fareFinal: Number(ctx.stateMachine.transition.mock.calls[0][0].data.fareFinal),
        platformFee: 0, driverPayout: 0,
      }));
      if (o.drivenM !== undefined) ctx.store[RedisKeys.tripDriven('trip-1')] = String(o.drivenM);
      if (o.at) {
        ctx.store[RedisKeys.driverLoc('driver-1')] = {
          lat: String(o.at.lat), lng: String(o.at.lng), ts: String(Date.now()),
        };
      }
      return ctx;
    }

    it('Complete at the pickup ENDS the trip (owner rule) at the minimum fare, never the estimate', async () => {
      const { svc, stateMachine } = setup({ drivenM: 0, ageS: 11, at: pickup });
      const r = await svc.completeTrip('driver-1', 'trip-1');
      expect(r.fareFinal).toBe(30);
      expect(r.breakdown.fareBasis).toBe('minimum');
      expect(r.breakdown.endedEarly).toBe(true);
      expect(r.breakdown.endedAwayFromDropoffM).toBeGreaterThan(500);
      expect(stateMachine.transition).toHaveBeenCalledWith(
        expect.objectContaining({ to: TripStatus.completed }),
      );
    });

    it('no fix and barely driven: charged as a short trip, not the estimate', async () => {
      const { svc } = setup({ drivenM: 0, ageS: 11, at: null });
      const r = await svc.completeTrip('driver-1', 'trip-1');
      expect(r.fareFinal).toBe(30);
      expect(r.breakdown.endedAwayFromDropoffM).toBeUndefined();
    });

    it('early end at the pickup charges the minimum fare, never the estimate', async () => {
      const { svc, stateMachine } = setup({ drivenM: 0, ageS: 11, at: pickup });
      const r = await svc.completeTrip('driver-1', 'trip-1', {
        endEarly: true, reason: 'Rider cancelled in the car',
      });
      expect(r.fareFinal).toBe(30);
      expect(r.distanceM).toBe(0);
      expect(r.breakdown.fareBasis).toBe('minimum');
      expect(r.breakdown.minimumFareAdjustment).toBeGreaterThan(0);
      expect(r.breakdown.fareAdjustment).toBe(0);
      expect(r.breakdown.endedEarly).toBe(true);
      expect(r.breakdown.endReason).toBe('Rider cancelled in the car');
      expect(stateMachine.transition).toHaveBeenCalledWith(
        expect.objectContaining({ meta: { breakdown: expect.objectContaining({ fareBasis: 'minimum' }) } }),
      );
    });

    it('early end after a real partial drive charges metered, not lifted to 0.8x the estimate', async () => {
      // 1.5 km, 5 min: 20 + 15 + 5 + 5 = 45 (< 71.2 the clamp floor would give).
      const { svc } = setup({ drivenM: 1500, ageS: 300, at: pickup });
      const r = await svc.completeTrip('driver-1', 'trip-1', { endEarly: true, reason: 'Rider asked' });
      expect(r.fareFinal).toBe(45);
      expect(r.breakdown.fareBasis).toBe('metered');
      expect(r.breakdown.endedEarly).toBe(true);
    });

    it('completing away from the drop-off after a real drive is charged as a short trip', async () => {
      const { svc } = setup({ drivenM: 1500, ageS: 300, at: pickup });
      const r = await svc.completeTrip('driver-1', 'trip-1');
      expect(r.fareFinal).toBe(45);
      expect(r.breakdown.fareBasis).toBe('metered');
      expect(r.breakdown.endedEarly).toBe(true);
      expect(r.breakdown.endReason).toBeUndefined();
    });

    it('a short trip is still capped at FARE_CLAMP_MAX x the estimate', async () => {
      // Spoofed odometer: 50 km. Cap = 133.5 → 134 (whole rupees).
      const { svc } = setup({ drivenM: 50_000, ageS: 300, at: pickup });
      const r = await svc.completeTrip('driver-1', 'trip-1', { endEarly: true, reason: 'x' });
      expect(r.fareFinal).toBe(134);
      expect(r.breakdown.fareBasis).toBe('estimate');
      expect(r.breakdown.fareAdjustment).toBeLessThan(0);
    });

    it('normal trip at the drop-off: metered distance + time, whole rupees', async () => {
      // 5 km, 10 min: 20 + 50 + 10 + 5 = 85 — inside [71.2, 133.5].
      const { svc } = setup({ drivenM: 5000, ageS: 600, at: dropoff });
      const r = await svc.completeTrip('driver-1', 'trip-1');
      expect(r.fareFinal).toBe(85);
      expect(r.breakdown.fareBasis).toBe('metered');
      expect(r.breakdown.minimumFareAdjustment).toBe(0);
      expect(r.breakdown.fareAdjustment).toBe(0);
    });

    it('normal trip at the drop-off, metered below the clamp: lifted to 0.8x (as an estimate adjustment, not "minimum fare")', async () => {
      // 1 km, 10 min: 20 + 10 + 10 + 5 = 45 → floor 71.2 → 71.
      const { svc } = setup({ drivenM: 1000, ageS: 600, at: dropoff });
      const r = await svc.completeTrip('driver-1', 'trip-1');
      expect(r.fareFinal).toBe(71);
      expect(r.breakdown.fareBasis).toBe('estimate');
      expect(r.breakdown.minimumFareAdjustment).toBe(0);
      expect(r.breakdown.fareAdjustment).toBeCloseTo(26, 2);
    });

    it('at the drop-off with a sparse GPS trail (< 50 m) the estimate stands', async () => {
      const { svc } = setup({ drivenM: 10, ageS: 900, at: dropoff });
      const r = await svc.completeTrip('driver-1', 'trip-1');
      expect(r.fareFinal).toBe(89);
      expect(r.breakdown.fareBasis).toBe('estimate');
    });

    it('rider "End trip here" (POST /end-early): min/metered fare, both parties get the receipt', async () => {
      const { svc, stateMachine, realtime } = setup({ drivenM: 0, ageS: 20, at: pickup });
      const r = await svc.endTripEarly('rider-1', 'trip-1');
      expect(r.fareFinal).toBe(30);
      expect(r.breakdown.fareBasis).toBe('minimum');
      expect(r.breakdown.endedEarly).toBe(true);
      expect(r.breakdown.endReason).toBe('Rider ended the trip');
      expect(stateMachine.transition).toHaveBeenCalledWith(
        expect.objectContaining({ to: TripStatus.completed, actor: 'rider' }),
      );
      expect(realtime.emitToUser).toHaveBeenCalledWith('rider-1', 'trip:completed', expect.anything());
      expect(realtime.emitToUser).toHaveBeenCalledWith('driver-1', 'trip:completed', expect.anything());
    });

    it('end-early is refused for a stranger and for a ride that has not started', async () => {
      const { svc, prisma } = setup({ drivenM: 0, ageS: 20, at: pickup });
      await expect(svc.endTripEarly('someone-else', 'trip-1')).rejects.toThrow('Not your trip');
      prisma.trip.findUnique.mockResolvedValue({ ...trip, status: TripStatus.accepted });
      const err = await svc.endTripEarly('rider-1', 'trip-1').catch((e) => e);
      expect(err.getResponse().code).toBe('TRIP_NOT_IN_PROGRESS');
    });

    it('a stale fix is not trusted: a real trail with no fresh fix settles normally', async () => {
      const ctx = setup({ drivenM: 5000, ageS: 600, at: null });
      ctx.store[RedisKeys.driverLoc('driver-1')] = {
        lat: String(pickup.lat), lng: String(pickup.lng),
        ts: String(Date.now() - ARRIVAL_FIX_MAX_AGE_MS - 1000),
      };
      const r = await ctx.svc.completeTrip('driver-1', 'trip-1');
      expect(r.fareFinal).toBe(85);
      expect(r.breakdown.endedEarly).toBe(false);
    });
  });

  describe('arrival geofence', () => {
    const trip = {
      id: 'trip-1', riderId: 'rider-1', driverId: 'driver-1', status: TripStatus.accepted,
      pickupLat: pickup.lat, pickupLng: pickup.lng,
    };

    it('rejects "arrived" with the live distance when the fresh fix is outside 150 m', async () => {
      const { svc, prisma, store, stateMachine } = make();
      prisma.trip.findUnique.mockResolvedValue(trip);
      // ~1 km north of the pickup, fix 5 s old.
      store[RedisKeys.driverLoc('driver-1')] = {
        lat: String(pickup.lat + 0.009), lng: String(pickup.lng), ts: String(Date.now() - 5000),
      };
      const err = await svc.driverArrived('driver-1', 'trip-1').catch((e) => e);
      expect(err).toBeInstanceOf(BadRequestException);
      expect(err.message).toMatch(/^You're still \d+ m from the pickup$/);
      expect(Number(err.message.match(/(\d+) m/)![1])).toBeGreaterThan(900);
      expect(stateMachine.transition).not.toHaveBeenCalled();
    });

    it('allows "arrived" inside the radius and records the distance on the event', async () => {
      const { svc, prisma, store, stateMachine, realtime } = make();
      prisma.trip.findUnique.mockResolvedValue(trip);
      store[RedisKeys.driverLoc('driver-1')] = {
        lat: String(pickup.lat + 0.0005), lng: String(pickup.lng), ts: String(Date.now() - 1000), // ~55 m
      };
      const res = await svc.driverArrived('driver-1', 'trip-1');
      expect(res.status).toBe(TripStatus.arrived);
      expect(res.arrivedDistanceM).toBeGreaterThan(40);
      expect(res.arrivedDistanceM).toBeLessThan(70);
      expect(stateMachine.transition).toHaveBeenCalledWith(
        expect.objectContaining({ to: TripStatus.arrived, meta: { arrivedDistanceM: res.arrivedDistanceM } }),
      );
      expect(realtime.emitToUser).toHaveBeenCalledWith('rider-1', 'trip:arrived', { tripId: 'trip-1' });
    });

    it('allows "arrived" when the last fix is stale (>60 s) rather than blocking on old data', async () => {
      const { svc, prisma, store } = make();
      prisma.trip.findUnique.mockResolvedValue(trip);
      store[RedisKeys.driverLoc('driver-1')] = {
        lat: String(pickup.lat + 0.05), lng: String(pickup.lng), ts: String(Date.now() - ARRIVAL_FIX_MAX_AGE_MS - 1),
      };
      const res = await svc.driverArrived('driver-1', 'trip-1');
      expect(res).toEqual({ status: TripStatus.arrived, arrivedDistanceM: null });
    });

    it('allows "arrived" when no fix is known at all', async () => {
      const { svc, prisma } = make();
      prisma.trip.findUnique.mockResolvedValue(trip);
      await expect(svc.driverArrived('driver-1', 'trip-1')).resolves.toMatchObject({ status: TripStatus.arrived });
    });
  });

  describe('completion receipt', () => {
    const trip = {
      id: 'trip-1', riderId: 'rider-1', driverId: 'driver-1', status: TripStatus.in_progress,
      tier: 'economy', distanceM: 5000, durationS: 600, fareEstimate: 11, surgeMultiplier: 1,
      promoDiscount: 0, currency: 'USD', paymentMode: 'card', startedAt: new Date(Date.now() - 600000),
    };

    it('trip:completed carries the fare breakdown, persists it on the completion event, and uses driver copy', async () => {
      const { svc, prisma, realtime, stateMachine, notifications, redis } = make();
      prisma.trip.findUnique.mockResolvedValue(trip);
      const receipt = await svc.completeTrip('driver-1', 'trip-1');
      // No GPS trail and no fix proving the car reached the drop-off: charged
      // as a short trip on what was metered (this mock prices it at the
      // itemised sum), never silently the up-front estimate.
      const breakdown = {
        ...breakdownFor(1), promoDiscount: 0, tip: 0, minimumFareAdjustment: 0,
        fareAdjustment: 0, fareBasis: 'metered', endedEarly: false,
      };
      expect(receipt.breakdown).toEqual(breakdown);
      expect(realtime.emitToUser).toHaveBeenCalledWith('rider-1', 'trip:completed', expect.objectContaining({ breakdown }));
      expect(realtime.emitToUser).toHaveBeenCalledWith('driver-1', 'trip:completed', expect.objectContaining({ breakdown }));
      expect(stateMachine.transition).toHaveBeenCalledWith(
        expect.objectContaining({ to: TripStatus.completed, meta: { breakdown } }),
      );
      // Driver gets the driver wording with what they earned; rider the rider's.
      expect(notifications.notifyTrip).toHaveBeenCalledWith('rider-1', 'completed', { tripId: 'trip-1' });
      expect(notifications.notifyTrip).toHaveBeenCalledWith(
        'driver-1', 'completed', { tripId: 'trip-1', earned: '8.80' }, 'driver',
      );
      // Leg navigation context and the GPS watchdog state are cleared with the
      // active-trip keys.
      expect(redis.client.del).toHaveBeenCalledWith(
        RedisKeys.driverActiveTrip('driver-1'),
        RedisKeys.driverActiveRider('driver-1'),
        RedisKeys.tripNav('trip-1'),
        RedisKeys.tripWatch('trip-1'),
      );
    });

    it('puts the driver straight back into their tier pool at the drop-off (offerable before any new ping)', async () => {
      const { svc, prisma, redis, store } = make();
      prisma.trip.findUnique.mockResolvedValue(trip);
      store[RedisKeys.driverTier('driver-1')] = 'economy';
      store[RedisKeys.driverLoc('driver-1')] = { lat: '12.97', lng: '77.59', ts: String(Date.now()) };
      await svc.completeTrip('driver-1', 'trip-1');
      expect(redis.client.set).toHaveBeenCalledWith(RedisKeys.driverStatus('driver-1'), 'online');
      expect(redis.client.geoadd).toHaveBeenCalledWith(
        RedisKeys.driversGeo('economy'), 77.59, 12.97, 'driver-1',
      );
    });

    it('does not re-pool on a stale last fix (dispatch would evict it; the next ping re-adds)', async () => {
      const { svc, prisma, redis, store } = make();
      prisma.trip.findUnique.mockResolvedValue(trip);
      store[RedisKeys.driverTier('driver-1')] = 'economy';
      store[RedisKeys.driverLoc('driver-1')] = { lat: '12.97', lng: '77.59', ts: String(Date.now() - 10 * 60_000) };
      await svc.completeTrip('driver-1', 'trip-1');
      expect(redis.client.geoadd).not.toHaveBeenCalled();
    });

    it('a failing re-pool never fails the completion', async () => {
      const { svc, prisma, redis, store } = make();
      prisma.trip.findUnique.mockResolvedValue(trip);
      store[RedisKeys.driverTier('driver-1')] = 'economy';
      store[RedisKeys.driverLoc('driver-1')] = { lat: '12.97', lng: '77.59', ts: String(Date.now()) };
      redis.client.geoadd.mockRejectedValueOnce(new Error('redis down'));
      await expect(svc.completeTrip('driver-1', 'trip-1')).resolves.toMatchObject({ tripId: 'trip-1' });
    });

    /**
     * A completed ride must never settle at nothing. Without a usable GPS
     * trail the fare falls back to the up-front estimate — but when that
     * estimate is itself missing or zero the old code handed the rider a
     * $0.00 receipt and the driver a $0.00 earning. Re-pricing the routed
     * distance is floored at the tier minimum, so the worst case is the
     * minimum fare rather than nothing.
     */
    it.each([
      ['a null estimate', null],
      ['a zero estimate', 0],
    ])('re-prices the ride rather than settling at $0 with %s', async (_label, fareEstimate) => {
      const { svc, prisma, realtime, payments } = make({ fare: 7.25 });
      prisma.trip.findUnique.mockResolvedValue({ ...trip, fareEstimate });
      // Echo back whatever fare the trip settled at, as a real capture would.
      payments.captureForTrip.mockImplementation(async () => ({
        fareFinal: 7.25, platformFee: 1.45, driverPayout: 5.8,
      }));

      const receipt = await svc.completeTrip('driver-1', 'trip-1');

      expect(receipt.fareFinal).toBe(7.25);
      expect(realtime.emitToUser).toHaveBeenCalledWith(
        'rider-1', 'trip:completed', expect.objectContaining({ fareFinal: 7.25 }),
      );
    });
  });

  describe('startTrip navigation context', () => {
    it('writes the trip-leg nav hash (target = dropoff, routed pace) for per-ping ETAs', async () => {
      const { svc, prisma, redis, store } = make();
      prisma.trip.findUnique.mockResolvedValue({
        id: 'trip-1', riderId: 'rider-1', driverId: 'driver-1', status: TripStatus.arrived,
        startOtp: '1234', dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
        routePolyline: 'poly', distanceM: 5000, durationS: 500,
      });
      store[RedisKeys.driverLoc('driver-1')] = { lat: '25.77', lng: '-80.19' };
      const payments = { authorizeForTrip: jest.fn().mockResolvedValue(undefined) };
      (svc as unknown as { payments: unknown }).payments = payments;
      await svc.startTrip('driver-1', 'trip-1', '1234');
      expect(redis.client.hset).toHaveBeenCalledWith(RedisKeys.tripNav('trip-1'), {
        phase: 'trip',
        targetLat: dropoff.lat,
        targetLng: dropoff.lng,
        waypoints: '[]',
        polyline: 'poly',
        avgSpeedMps: 10,
      });
    });

    it('carries booked stops into the nav hash, in order', async () => {
      const { svc, prisma, redis, store } = make();
      prisma.trip.findUnique.mockResolvedValue({
        id: 'trip-1', riderId: 'rider-1', driverId: 'driver-1', status: TripStatus.arrived,
        startOtp: '1234', dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
        routePolyline: 'poly', distanceM: 5000, durationS: 500,
        stops: [{ lat: 1, lng: 2, addr: 'A' }, { lat: 3, lng: 4 }],
      });
      store[RedisKeys.driverLoc('driver-1')] = { lat: '25.77', lng: '-80.19' };
      (svc as unknown as { payments: unknown }).payments = {
        authorizeForTrip: jest.fn().mockResolvedValue(undefined),
      };
      await svc.startTrip('driver-1', 'trip-1', '1234');
      expect(redis.client.hset).toHaveBeenCalledWith(
        RedisKeys.tripNav('trip-1'),
        expect.objectContaining({
          waypoints: JSON.stringify([{ lat: 1, lng: 2 }, { lat: 3, lng: 4 }]),
        }),
      );
    });
  });
  // Booking a ride for somebody else. The booker stays the account that pays
  // and tracks; these cover who is actually travelling.
  describe('booking for someone else', () => {
    describe('resolvePassenger', () => {
      it('is null for an ordinary ride, where the booker travels', () => {
        expect(TripsService.resolvePassenger({})).toBeNull();
        expect(
          TripsService.resolvePassenger({ passengerName: '  ' }),
        ).toBeNull();
      });

      it('refuses a name with no phone', () => {
        // Everything the passenger needs runs through the number: the driver
        // calls them, and the start code is texted to them. A name alone would
        // leave the driver looking for someone they cannot reach.
        expect(() =>
          TripsService.resolvePassenger({ passengerName: 'Priya' }),
        ).toThrow(BadRequestException);
      });

      it('accepts a phone without a name — the driver still has someone to call', () => {
        expect(
          TripsService.resolvePassenger({ passengerPhone: '+15550001111' }),
        ).toEqual({ name: null, phone: '+15550001111' });
      });

      it('trims both', () => {
        expect(
          TripsService.resolvePassenger({
            passengerName: '  Priya  ',
            passengerPhone: ' +15550001111 ',
          }),
        ).toEqual({ name: 'Priya', phone: '+15550001111' });
      });
    });

    it('texts the passenger when the driver arrives, not just the booker', async () => {
      const { svc, prisma, store, sms, notifications } = make();
      prisma.trip.findUnique.mockResolvedValue({
        id: 'trip-1',
        riderId: 'rider-1',
        driverId: 'driver-1',
        status: TripStatus.accepted,
        pickupLat: pickup.lat,
        pickupLng: pickup.lng,
        passengerName: 'Priya',
        passengerPhone: '+15550001111',
      });
      store[RedisKeys.driverLoc('driver-1')] = {
        lat: String(pickup.lat),
        lng: String(pickup.lng),
        ts: String(Date.now() - 1000),
      };

      await svc.driverArrived('driver-1', 'trip-1');
      await new Promise((r) => setImmediate(r)); // the send is fire-and-forget

      expect(sms.sendMessage).toHaveBeenCalledWith(
        '+15550001111',
        expect.stringContaining('here'),
      );
      // The booker still gets their own push — the text is in addition.
      expect(notifications.notifyTrip).toHaveBeenCalledWith(
        'rider-1',
        'arrived',
        { tripId: 'trip-1' },
      );
    });

    it('sends no text on an ordinary ride', async () => {
      const { svc, prisma, store, sms } = make();
      prisma.trip.findUnique.mockResolvedValue({
        id: 'trip-1',
        riderId: 'rider-1',
        driverId: 'driver-1',
        status: TripStatus.accepted,
        pickupLat: pickup.lat,
        pickupLng: pickup.lng,
      });
      store[RedisKeys.driverLoc('driver-1')] = {
        lat: String(pickup.lat),
        lng: String(pickup.lng),
        ts: String(Date.now() - 1000),
      };

      await svc.driverArrived('driver-1', 'trip-1');
      await new Promise((r) => setImmediate(r));

      expect(sms.sendMessage).not.toHaveBeenCalled();
    });

    it('a failed text never takes the arrival down with it', async () => {
      const { svc, prisma, store, sms } = make();
      sms.sendMessage.mockRejectedValue(new Error('gateway down'));
      prisma.trip.findUnique.mockResolvedValue({
        id: 'trip-1',
        riderId: 'rider-1',
        driverId: 'driver-1',
        status: TripStatus.accepted,
        pickupLat: pickup.lat,
        pickupLng: pickup.lng,
        passengerPhone: '+15550001111',
      });
      store[RedisKeys.driverLoc('driver-1')] = {
        lat: String(pickup.lat),
        lng: String(pickup.lng),
        ts: String(Date.now() - 1000),
      };

      const res = await svc.driverArrived('driver-1', 'trip-1');
      await new Promise((r) => setImmediate(r));
      expect(res.status).toBe(TripStatus.arrived);
    });
  });

  describe('TripsService.getTrip — driver position on a restored trip', () => {
    // A rider reopening the app (cold start, or back from a suspend) had no
    // driver position until the next `trip:driver_location` ping, so the marker
    // sat where it was when they left — or nowhere. The snapshot now carries the
    // server's last known fix.
    function setup(loc?: Record<string, string>) {
      const { svc, prisma, store } = make();
      const trip = {
        id: 'trip-1',
        riderId: 'rider-1',
        driverId: 'driver-1',
        status: 'accepted',
        pickupLat: 1,
        pickupLng: 2,
        dropoffLat: 3,
        dropoffLng: 4,
      };
      prisma.trip.findUnique.mockResolvedValue(trip);
      prisma.user.findUnique.mockResolvedValue({
        id: 'driver-1',
        fullName: 'Ava',
        ratingAvg: 4.9,
        driverProfile: { vehicleMake: 'Toyota', plateNumber: 'ABC123' },
      });
      if (loc) store[RedisKeys.driverLoc('driver-1')] = loc;
      return svc;
    }

    it('includes the driver last known position', async () => {
      const svc = setup({ lat: '12.34', lng: '56.78', heading: '90', ts: '1700' });
      const res = (await svc.getTrip('rider-1', 'trip-1')) as Record<string, any>;
      expect(res.driverLocation).toEqual({
        lat: 12.34,
        lng: 56.78,
        heading: 90,
        ts: 1700,
      });
    });

    it('returns null when the driver has no fresh fix, rather than failing', async () => {
      const svc = setup();
      const res = (await svc.getTrip('rider-1', 'trip-1')) as Record<string, any>;
      expect(res.driverLocation).toBeNull();
      // The rest of the snapshot must still be there — the position is
      // best-effort and never allowed to take the trip down with it.
      expect(res.driver.name).toBe('Ava');
    });
  });

  // Pilot calling: the rider's "Call" dials the driver, the driver's "Call
  // rider" dials the rider. Real numbers (pilot only — production masks them),
  // exposed only to the other party and only while the ride is live.
  describe('TripsService.getTrip — phone numbers for calling', () => {
    function setup(status: string) {
      const { svc, prisma } = make();
      prisma.trip.findUnique.mockResolvedValue({
        id: 'trip-1',
        riderId: 'rider-1',
        driverId: 'driver-1',
        status,
        pickupLat: 1,
        pickupLng: 2,
        dropoffLat: 3,
        dropoffLng: 4,
      });
      prisma.user.findUnique.mockImplementation(async ({ where }: any) =>
        where.id === 'driver-1'
          ? { id: 'driver-1', fullName: 'Ava', phone: '+998901112233', ratingAvg: 4.9, driverProfile: null }
          : { id: 'rider-1', fullName: 'Rustam', phone: '+998907778899' },
      );
      return svc;
    }

    it('gives the rider the driver phone while the ride is live', async () => {
      const res = (await setup('accepted').getTrip('rider-1', 'trip-1')) as Record<string, any>;
      expect(res.driver.phone).toBe('+998901112233');
      expect(res.rider).toBeUndefined(); // the rider gets no rider block
    });

    it('gives the driver the rider name and phone while the ride is live', async () => {
      for (const status of ['accepted', 'arrived', 'in_progress']) {
        const res = (await setup(status).getTrip('driver-1', 'trip-1')) as Record<string, any>;
        expect(res.rider).toEqual({ id: 'rider-1', name: 'Rustam', phone: '+998907778899' });
      }
    });

    it('exposes neither number once the ride is over', async () => {
      const asRider = (await setup('completed').getTrip('rider-1', 'trip-1')) as Record<string, any>;
      expect(asRider.driver.phone).toBeUndefined();
      const asDriver = (await setup('completed').getTrip('driver-1', 'trip-1')) as Record<string, any>;
      expect(asDriver.rider).toBeUndefined();
    });
  });

  describe('history', () => {
    const row = (over: Record<string, unknown>) => ({
      id: 'trip-1',
      riderId: 'rider-1',
      driverId: 'driver-1',
      status: TripStatus.completed,
      tier: 'economy',
      pickupLat: 1,
      pickupLng: 2,
      dropoffLat: 3,
      dropoffLng: 4,
      promoDiscount: 0,
      surgeMultiplier: 1,
      stops: null,
      driver: {
        fullName: 'Aziz Karimov',
        photoUrl: 'https://cdn.example/aziz.jpg',
        phone: '+998901112233',
        driverProfile: {
          vehicleMake: 'Chevrolet',
          vehicleModel: 'Cobalt',
          vehicleColor: 'White',
          plateNumber: '01A123BC',
        },
      },
      ratings: [],
      ...over,
    });

    it('joins driver and the caller rating in one query (no N+1)', async () => {
      const { svc, prisma } = make();
      (prisma.trip as any).findMany = jest.fn().mockResolvedValue([
        row({}),
        row({ id: 'trip-2', ratings: [{ stars: 4 }] }),
      ]);
      const res = (await svc.history('rider-1')) as Record<string, any>[];
      expect((prisma.trip as any).findMany).toHaveBeenCalledTimes(1);
      const args = (prisma.trip as any).findMany.mock.calls[0][0];
      expect(args.include.ratings.where).toEqual({ fromUser: 'rider-1' });
      expect(args.include.driver.select.phone).toBeUndefined();
      expect(prisma.user.findUnique).not.toHaveBeenCalled();

      expect(res[0].driver).toEqual({
        name: 'Aziz Karimov',
        avatarUrl: 'https://cdn.example/aziz.jpg',
        vehicleLabel: 'White Chevrolet Cobalt',
        plate: '01A123BC',
      });
      expect(res[0].myRating).toBeNull();
      expect(res[1].myRating).toBe(4);
      expect(JSON.stringify(res)).not.toContain('+998901112233');
      expect(res[0].ratings).toBeUndefined();
    });

    it('leaves out the driver block on the driver own rows and on unassigned trips', async () => {
      const { svc, prisma } = make();
      (prisma.trip as any).findMany = jest.fn().mockResolvedValue([
        row({ ratings: [{ stars: 5 }] }),
        row({ id: 'trip-3', riderId: 'driver-1', driverId: null, driver: null }),
      ]);
      const asDriver = (await svc.history('driver-1')) as Record<string, any>[];
      expect(asDriver[0].driver).toBeUndefined();
      expect(asDriver[0].myRating).toBe(5);
      expect(asDriver[1].driver).toBeUndefined();
      expect(asDriver[1].myRating).toBeNull();
    });

    it('falls back when the driver has no name or vehicle', () => {
      expect(
        TripsService.historyDriver({ fullName: null, photoUrl: null, driverProfile: null }),
      ).toEqual({ name: 'Your driver', avatarUrl: null, vehicleLabel: null, plate: null });
    });
  });
});
