import {
  FALLBACK_ETA_MPS,
  LocationService,
  MAX_BROADCAST_ACCURACY_M,
  MAX_METER_ACCURACY_M,
  MAX_PLAUSIBLE_SPEED_MPS,
} from './location.service';
import { encodePolyline, haversineMeters } from '../geo/geo.util';

/**
 * The odometer step itself is a Redis Lua script (exercised against a real
 * Redis manually / in e2e); these tests pin the server-side gating around it:
 * noisy fixes are never metered, and the script receives the timestamp and
 * speed ceiling it needs for the implied-speed check.
 */
describe('LocationService metering gate', () => {
  function build(
    opts: {
      status?: string;
      tripId?: string | null;
      nav?: Record<string, string | number> | null;
    } = {},
  ) {
    const store: Record<string, string | null> = {
      'driver:d1:status': opts.status ?? 'on_trip',
      'driver:d1:activeTrip': opts.tripId === undefined ? 't1' : opts.tripId,
      'driver:d1:activeRider': 'r1',
      'driver:d1:tier': 'economy',
    };
    const client = {
      hset: jest.fn().mockResolvedValue(1),
      hgetall: jest.fn(async (k: string) =>
        k === 'trip:t1:nav' && opts.nav ? { ...opts.nav } : {},
      ),
      get: jest.fn(async (k: string) => store[k] ?? null),
      geoadd: jest.fn().mockResolvedValue(1),
      eval: jest.fn().mockResolvedValue('0'),
    };
    const realtime = { emitToUser: jest.fn() };
    const svc = new LocationService({ client } as never, realtime as never);
    return { svc, client, realtime };
  }

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
