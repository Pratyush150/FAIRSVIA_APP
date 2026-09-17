import {
  FALLBACK_ETA_MPS,
  LocationService,
  MAX_BROADCAST_ACCURACY_M,
  MAX_METER_ACCURACY_M,
  MAX_PLAUSIBLE_SPEED_MPS,
  OFF_ROUTE_PINGS,
  STOPPED_AFTER_S,
} from './location.service';
import { encodePolyline, haversineMeters } from '../geo/geo.util';

/**
 * Shared fake Redis/realtime rig. The hash store is real enough that a test
 * can drive several pings through one service and have the watchdog streak and
 * stop-anchor carry between them the way Redis would.
 */
function build(
  opts: {
    status?: string;
    tripId?: string | null;
    nav?: Record<string, string | number> | null;
    watch?: Record<string, string>;
  } = {},
) {
  const store: Record<string, string | null> = {
    'driver:d1:status': opts.status ?? 'on_trip',
    'driver:d1:activeTrip': opts.tripId === undefined ? 't1' : opts.tripId,
    'driver:d1:activeRider': 'r1',
    'driver:d1:tier': 'economy',
  };
  // Hash store backing the watchdog state, so a test can drive several pings
  // through one service and have the streak/anchor carry between them the way
  // real Redis would.
  const hashes: Record<string, Record<string, string>> = {
    'trip:t1:nav': opts.nav
      ? Object.fromEntries(
          Object.entries(opts.nav).map(([k, v]) => [k, String(v)]),
        )
      : {},
    ...(opts.watch ? { 'trip:t1:watch': { ...opts.watch } } : {}),
  };
  const hset = jest.fn(
    async (k: string, a: unknown, b?: unknown) => {
      const h = (hashes[k] ??= {});
      if (typeof a === 'object' && a !== null) {
        for (const [f, v] of Object.entries(a as Record<string, unknown>)) {
          h[f] = String(v);
        }
      } else {
        h[String(a)] = String(b);
      }
      return 1;
    },
  );
  const hdel = jest.fn(async (k: string, ...fields: string[]) => {
    const h = hashes[k];
    if (!h) return 0;
    for (const f of fields) delete h[f];
    return fields.length;
  });
  const hsetnx = jest.fn(async (k: string, f: string, v: string) => {
    const h = (hashes[k] ??= {});
    if (h[f] !== undefined) return 0;
    h[f] = v;
    return 1;
  });
  const client = {
    hset,
    hdel,
    hsetnx,
    expire: jest.fn().mockResolvedValue(1),
    hgetall: jest.fn(async (k: string) => ({ ...(hashes[k] ?? {}) })),
    get: jest.fn(async (k: string) => store[k] ?? null),
    geoadd: jest.fn().mockResolvedValue(1),
    eval: jest.fn().mockResolvedValue('0'),
    // Minimal ioredis-style pipeline: queue the calls, run them on exec().
    pipeline: jest.fn(() => {
      const queued: Array<() => Promise<unknown>> = [];
      const p = {
        hset: (...args: unknown[]) => {
          queued.push(() => hset(...(args as [string, unknown, unknown?])));
          return p;
        },
        hdel: (...args: unknown[]) => {
          queued.push(() => hdel(...(args as [string, ...string[]])));
          return p;
        },
        expire: () => p,
        exec: async () => {
          for (const run of queued) await run();
          return [];
        },
      };
      return p;
    }),
  };
  const realtime = { emitToUser: jest.fn() };
  const notifications = { notifyTrip: jest.fn().mockResolvedValue(undefined) };
  const geo = { route: jest.fn() };
  const svc = new LocationService(
    { client } as never,
    realtime as never,
    notifications as never,
    geo as never,
  );
  return { svc, client, realtime, notifications, geo, hashes };
}

/**
 * The odometer step itself is a Redis Lua script (exercised against a real
 * Redis manually / in e2e); these tests pin the server-side gating around it:
 * noisy fixes are never metered, and the script receives the timestamp and
 * speed ceiling it needs for the implied-speed check.
 */
describe('LocationService metering gate', () => {

  it('meters a fix with acceptable accuracy, passing the timestamp and speed cap', async () => {
    const { svc, client } = build();
    const before = Date.now();
    await svc.ingest('d1', { lat: 25.76, lng: -80.19, accuracy: 12 });
    expect(client.eval).toHaveBeenCalledTimes(1);
    const args = client.eval.mock.calls[0];
    // KEYS: driven counter + last point; ARGV: lat, lng, maxSeg, nowMs, maxSpeed
    expect(args[1]).toBe(2);
    expect(args[2]).toBe('trip:t1:driven');
    expect(args[3]).toBe('trip:t1:meterLast');
    expect(args[4]).toBe(25.76);
    expect(args[5]).toBe(-80.19);
    expect(args[6]).toBe(2000);
    expect(args[7]).toBeGreaterThanOrEqual(before);
    expect(args[8]).toBe(MAX_PLAUSIBLE_SPEED_MPS);
    expect(MAX_PLAUSIBLE_SPEED_MPS).toBe(60);
  });

  it('meters when the device reports no accuracy (older clients)', async () => {
    const { svc, client } = build();
    await svc.ingest('d1', { lat: 25.76, lng: -80.19 });
    expect(client.eval).toHaveBeenCalledTimes(1);
  });

  it('neither meters nor shows the rider a fix flagged as noisier than 100 m', async () => {
    const { svc, client, realtime } = build();
    await svc.ingest('d1', { lat: 25.76, lng: -80.19, accuracy: MAX_METER_ACCURACY_M + 1 });
    expect(client.eval).not.toHaveBeenCalled();
    // The stored position (presence / staleness) still updates, with accuracy.
    expect(client.hset).toHaveBeenCalledWith(
      'driver:d1:loc',
      expect.objectContaining({ lat: 25.76, lng: -80.19, accuracy: MAX_METER_ACCURACY_M + 1 }),
    );
    // ...but a 100 m+ blob is withheld from the rider's live map.
    expect(MAX_BROADCAST_ACCURACY_M).toBe(100);
    expect(realtime.emitToUser).not.toHaveBeenCalled();
  });

  it('meters a fix at exactly the accuracy limit', async () => {
    const { svc, client } = build();
    await svc.ingest('d1', { lat: 25.76, lng: -80.19, accuracy: MAX_METER_ACCURACY_M });
    expect(client.eval).toHaveBeenCalledTimes(1);
  });

  it('does not meter (or broadcast) when the driver is not on a trip', async () => {
    const { svc, client, realtime } = build({ status: 'online', tripId: null });
    await svc.ingest('d1', { lat: 25.76, lng: -80.19, accuracy: 5 });
    expect(client.eval).not.toHaveBeenCalled();
    expect(realtime.emitToUser).not.toHaveBeenCalled();
    expect(client.geoadd).toHaveBeenCalled(); // back in the matchable pool
  });

  // The rider broadcast now carries the full fix + a live ETA for the leg.
  describe('trip:driver_location payload + ETA refresh', () => {
    const pickup = { lat: 25.77, lng: -80.19 };

    it('includes speed, accuracy and the device ts, with nulls when unknown', async () => {
      const { svc, realtime } = build();
      await svc.ingest('d1', { lat: 25.76, lng: -80.19, heading: 90, speed: 12, accuracy: 8, ts: 1700000000000 });
      expect(realtime.emitToUser).toHaveBeenCalledWith('r1', 'trip:driver_location', {
        tripId: 't1',
        lat: 25.76,
        lng: -80.19,
        heading: 90,
        speed: 12,
        accuracy: 8,
        ts: 1700000000000,
        phase: null,
        etaSec: null,
        remainingM: null,
        etaSource: null,
      });
    });

    it('defaults ts to the server clock and accuracy to null for older clients', async () => {
      const { svc, realtime } = build();
      const before = Date.now();
      await svc.ingest('d1', { lat: 25.76, lng: -80.19 });
      const payload = realtime.emitToUser.mock.calls[0][2];
      expect(payload.accuracy).toBeNull();
      expect(payload.ts).toBeGreaterThanOrEqual(before);
    });

    it('recomputes ETA/remaining along the stored polyline at the routed pace', async () => {
      // A 3-vertex approach route; the driver is at the middle vertex, so the
      // remaining distance is exactly the last segment.
      const route = [{ lat: 25.75, lng: -80.19 }, { lat: 25.76, lng: -80.19 }, pickup];
      const lastSeg = haversineMeters(route[1], route[2]);
      const { svc, realtime } = build({
        nav: {
          phase: 'approach',
          targetLat: pickup.lat,
          targetLng: pickup.lng,
          polyline: encodePolyline(route),
          avgSpeedMps: 10,
        },
      });
      await svc.ingest('d1', { lat: 25.76, lng: -80.19, accuracy: 5 });
      const payload = realtime.emitToUser.mock.calls[0][2];
      expect(payload.phase).toBe('approach');
      expect(payload.etaSource).toBe('route');
      expect(payload.remainingM).toBe(Math.round(lastSeg));
      expect(payload.etaSec).toBe(Math.round(lastSeg / 10));
    });

    it('falls back to straight-line at 8 m/s when the leg has no polyline or pace', async () => {
      const { svc, realtime } = build({
        nav: { phase: 'trip', targetLat: pickup.lat, targetLng: pickup.lng, polyline: '', avgSpeedMps: '' },
      });
      await svc.ingest('d1', { lat: 25.76, lng: -80.19, accuracy: 5 });
      const payload = realtime.emitToUser.mock.calls[0][2];
      const straight = Math.round(haversineMeters({ lat: 25.76, lng: -80.19 }, pickup));
      expect(payload.phase).toBe('trip');
      expect(payload.etaSource).toBe('straight');
      expect(payload.remainingM).toBe(straight);
      expect(payload.etaSec).toBe(Math.round(straight / FALLBACK_ETA_MPS));
      expect(FALLBACK_ETA_MPS).toBe(8);
    });

    it('snaps a driver who is off the line onto the nearest segment (never negative ETA)', () => {
      const route = [{ lat: 25.75, lng: -80.19 }, { lat: 25.77, lng: -80.19 }];
      const est = LocationService.estimate(
        { lat: 25.765, lng: -80.185 }, // ~500 m east of the line, 3/4 along
        { phase: 'approach', target: route[1], polyline: encodePolyline(route), avgSpeedMps: 10 },
      );
      const quarter = haversineMeters(route[0], route[1]) / 4;
      expect(est.etaSource).toBe('route');
      expect(Math.abs(est.remainingM - quarter)).toBeLessThan(quarter * 0.05);
      expect(est.etaSec).toBeGreaterThanOrEqual(0);
    });
  });
});

/**
 * The rider-facing watchdogs. Both are "tell the rider once, then shut up until
 * the situation changes", so the tests care as much about what is NOT emitted
 * on the repeat pings as about the first alert.
 */
describe('LocationService rider watchdogs', () => {
  // A straight north-south trip route; "off route" means east of the line.
  const routeStart = { lat: 25.75, lng: -80.19 };
  const routeEnd = { lat: 25.79, lng: -80.19 };
  const onRoute = { lat: 25.77, lng: -80.19 };
  // ~1 km east of the line — well past OFF_ROUTE_M (120 m).
  const wayOff = { lat: 25.77, lng: -80.179 };

  function tripNav(phase: 'trip' | 'approach' = 'trip') {
    return {
      phase,
      targetLat: routeEnd.lat,
      targetLng: routeEnd.lng,
      polyline: encodePolyline([routeStart, routeEnd]),
      avgSpeedMps: 12,
    };
  }

  function eventsOf(realtime: { emitToUser: jest.Mock }, name: string) {
    return realtime.emitToUser.mock.calls.filter((c) => c[1] === name);
  }

  describe('off route', () => {
    it('alerts only after several consecutive deviating fixes, then once', async () => {
      const { svc, realtime, geo } = build({ nav: tripNav() });
      geo.route.mockResolvedValue({
        distanceM: 2000,
        durationS: 200,
        polyline: encodePolyline([wayOff, routeEnd]),
      });

      // One bad fix is noise, not a wrong turn.
      await svc.ingest('d1', { ...wayOff, accuracy: 5 });
      expect(eventsOf(realtime, 'trip:off_route')).toHaveLength(0);

      for (let i = 1; i < OFF_ROUTE_PINGS; i++) {
        await svc.ingest('d1', { ...wayOff, accuracy: 5 });
      }
      const alerts = eventsOf(realtime, 'trip:off_route');
      expect(alerts).toHaveLength(1);
      expect(alerts[0][0]).toBe('r1');
      expect(alerts[0][2].tripId).toBe('t1');
      expect(alerts[0][2].offsetM).toBeGreaterThan(120);

      // Still off route: the rider is not told again.
      await svc.ingest('d1', { ...wayOff, accuracy: 5 });
      await svc.ingest('d1', { ...wayOff, accuracy: 5 });
      expect(eventsOf(realtime, 'trip:off_route')).toHaveLength(1);
    });

    it('redraws the route from where the driver actually is', async () => {
      const { svc, realtime, geo, hashes } = build({ nav: tripNav() });
      const fresh = encodePolyline([wayOff, routeEnd]);
      geo.route.mockResolvedValue({ distanceM: 2000, durationS: 200, polyline: fresh });

      for (let i = 0; i < OFF_ROUTE_PINGS; i++) {
        await svc.ingest('d1', { ...wayOff, accuracy: 5 });
      }
      const updates = eventsOf(realtime, 'trip:route_updated');
      expect(updates).toHaveLength(1);
      expect(updates[0][2].polyline).toBe(fresh);
      // The stored leg is updated too, so the next ping's ETA uses the new line.
      expect(hashes['trip:t1:nav'].polyline).toBe(fresh);
      expect(geo.route).toHaveBeenCalledWith(
        { lat: wayOff.lat, lng: wayOff.lng },
        { lat: routeEnd.lat, lng: routeEnd.lng },
      );
    });

    it('a routing failure still alerts the rider and leaves the old line alone', async () => {
      const { svc, realtime, geo, hashes } = build({ nav: tripNav() });
      const original = hashes['trip:t1:nav'].polyline;
      geo.route.mockRejectedValue(new Error('OSRM down'));

      for (let i = 0; i < OFF_ROUTE_PINGS; i++) {
        await svc.ingest('d1', { ...wayOff, accuracy: 5 });
      }
      expect(eventsOf(realtime, 'trip:off_route')).toHaveLength(1);
      expect(eventsOf(realtime, 'trip:route_updated')).toHaveLength(0);
      expect(hashes['trip:t1:nav'].polyline).toBe(original);
    });

    it('re-arms once the driver is back on the route', async () => {
      const { svc, realtime, geo } = build({ nav: tripNav() });
      geo.route.mockRejectedValue(new Error('no routing')); // keep the old line

      for (let i = 0; i < OFF_ROUTE_PINGS; i++) {
        await svc.ingest('d1', { ...wayOff, accuracy: 5 });
      }
      expect(eventsOf(realtime, 'trip:off_route')).toHaveLength(1);

      await svc.ingest('d1', { ...onRoute, accuracy: 5 });
      expect(eventsOf(realtime, 'trip:back_on_route')).toHaveLength(1);

      // A second deviation is a new episode and alerts again.
      for (let i = 0; i < OFF_ROUTE_PINGS; i++) {
        await svc.ingest('d1', { ...wayOff, accuracy: 5 });
      }
      expect(eventsOf(realtime, 'trip:off_route')).toHaveLength(2);
    });

    it('never polices the approach leg — drivers pick their own road to a pickup', async () => {
      const { svc, realtime, geo } = build({ nav: tripNav('approach') });
      for (let i = 0; i < OFF_ROUTE_PINGS + 2; i++) {
        await svc.ingest('d1', { ...wayOff, accuracy: 5 });
      }
      expect(eventsOf(realtime, 'trip:off_route')).toHaveLength(0);
      expect(geo.route).not.toHaveBeenCalled();
    });
  });

  describe('stopped', () => {
    it('says nothing while the driver keeps moving, however old the anchor', async () => {
      // Anchored well past the threshold, but this fix is ~2 km away: the
      // driver has been driving, so the clock restarts rather than firing.
      const { svc, realtime } = build({
        nav: tripNav(),
        watch: {
          moveLat: String(routeStart.lat),
          moveLng: String(routeStart.lng),
          moveTs: String(Date.now() - (STOPPED_AFTER_S + 60) * 1000),
        },
      });
      await svc.ingest('d1', { ...onRoute, accuracy: 5 });
      expect(eventsOf(realtime, 'trip:driver_stopped')).toHaveLength(0);
    });

    it('alerts once when the driver has not moved for the threshold', async () => {
      const { svc, realtime, notifications } = build({
        nav: tripNav(),
        watch: {
          moveLat: String(onRoute.lat),
          moveLng: String(onRoute.lng),
          moveTs: String(Date.now() - (STOPPED_AFTER_S + 5) * 1000),
        },
      });
      await svc.ingest('d1', { ...onRoute, accuracy: 5 });
      const alerts = eventsOf(realtime, 'trip:driver_stopped');
      expect(alerts).toHaveLength(1);
      expect(alerts[0][0]).toBe('r1');
      expect(alerts[0][2].stoppedSec).toBeGreaterThanOrEqual(STOPPED_AFTER_S);
      expect(notifications.notifyTrip).toHaveBeenCalledWith('r1', 'driver_stopped', {
        tripId: 't1',
      });

      // Still parked: no second popup.
      await svc.ingest('d1', { ...onRoute, accuracy: 5 });
      expect(eventsOf(realtime, 'trip:driver_stopped')).toHaveLength(1);
    });

    it('tells the rider when the driver sets off again, and re-arms', async () => {
      const { svc, realtime } = build({
        nav: tripNav(),
        watch: {
          moveLat: String(onRoute.lat),
          moveLng: String(onRoute.lng),
          moveTs: String(Date.now() - (STOPPED_AFTER_S + 5) * 1000),
          stoppedAlerted: '1',
        },
      });
      // A fix ~1 km up the route: clearly moving again.
      await svc.ingest('d1', { lat: 25.78, lng: -80.19, accuracy: 5 });
      expect(eventsOf(realtime, 'trip:driver_moving')).toHaveLength(1);
      expect(eventsOf(realtime, 'trip:driver_stopped')).toHaveLength(0);
    });

    it('a brief halt at a light is not a stop', async () => {
      const { svc, realtime } = build({
        nav: tripNav(),
        watch: {
          moveLat: String(onRoute.lat),
          moveLng: String(onRoute.lng),
          moveTs: String(Date.now() - 30 * 1000),
        },
      });
      await svc.ingest('d1', { ...onRoute, accuracy: 5 });
      expect(eventsOf(realtime, 'trip:driver_stopped')).toHaveLength(0);
      expect(STOPPED_AFTER_S).toBe(180);
    });
  });
});
