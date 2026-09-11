import {
  LocationService,
  MAX_METER_ACCURACY_M,
  MAX_PLAUSIBLE_SPEED_MPS,
} from './location.service';

/**
 * The odometer step itself is a Redis Lua script (exercised against a real
 * Redis manually / in e2e); these tests pin the server-side gating around it:
 * noisy fixes are never metered, and the script receives the timestamp and
 * speed ceiling it needs for the implied-speed check.
 */
describe('LocationService metering gate', () => {
  function build(opts: { status?: string; tripId?: string | null } = {}) {
    const store: Record<string, string | null> = {
      'driver:d1:status': opts.status ?? 'on_trip',
      'driver:d1:activeTrip': opts.tripId === undefined ? 't1' : opts.tripId,
      'driver:d1:activeRider': 'r1',
      'driver:d1:tier': 'economy',
    };
    const client = {
      hset: jest.fn().mockResolvedValue(1),
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

  it('still streams but never meters a fix flagged as noisier than 100 m', async () => {
    const { svc, client, realtime } = build();
    await svc.ingest('d1', { lat: 25.76, lng: -80.19, accuracy: MAX_METER_ACCURACY_M + 1 });
    expect(client.eval).not.toHaveBeenCalled();
    // Position hash + rider broadcast still happen — only the fare odometer is gated.
    expect(client.hset).toHaveBeenCalledWith(
      'driver:d1:loc',
      expect.objectContaining({ lat: 25.76, lng: -80.19 }),
    );
    expect(realtime.emitToUser).toHaveBeenCalledWith(
      'r1',
      'trip:driver_location',
      expect.objectContaining({ tripId: 't1' }),
    );
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
});
