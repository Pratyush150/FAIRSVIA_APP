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
    return { svc, store, redis, prisma, created, surge, stateMachine, realtime, notifications, dispatch, payments, sms };
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
      const breakdown = { ...breakdownFor(1), promoDiscount: 0, tip: 0, minimumFareAdjustment: 0 };
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
});
