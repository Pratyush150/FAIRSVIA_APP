import { BadRequestException } from '@nestjs/common';
import { DispatchService } from '../../dispatch/dispatch.service';
import {
  DESTINATION_MAX_ACTIVE_MS,
  autoOffReason,
  bringsCloser,
} from './destination.rules';
import { DestinationKeys, DestinationModeService } from './destination-mode.service';

// Tashkent-ish geometry. Driver downtown, home ~10 km north.
const DRIVER = { lat: 41.3, lng: 69.24 };
const HOME = { lat: 41.39, lng: 69.24 };
const TOWARD = { lat: 41.36, lng: 69.24 }; // ~3.3 km from home (≈33 % of 10 km)
const AWAY = { lat: 41.22, lng: 69.24 }; // further south, away from home
const SIDEWAYS = { lat: 41.3, lng: 69.3 }; // ~5 km east: barely closer, not 70 %

describe('destination rules', () => {
  it('offers only drop-offs within 70 % of the remaining distance', () => {
    expect(bringsCloser(DRIVER, TOWARD, HOME)).toBe(true);
    expect(bringsCloser(DRIVER, AWAY, HOME)).toBe(false);
    expect(bringsCloser(DRIVER, SIDEWAYS, HOME)).toBe(false);
  });

  it('auto-off after 2 h or within 500 m of the destination', () => {
    const t0 = 1_000_000;
    expect(autoOffReason(t0, t0 + 60_000, DRIVER, HOME)).toBeNull();
    expect(autoOffReason(t0, t0 + DESTINATION_MAX_ACTIVE_MS, DRIVER, HOME)).toBe('expired');
    const near = { lat: HOME.lat - 0.003, lng: HOME.lng }; // ~330 m
    expect(autoOffReason(t0, t0 + 60_000, near, HOME)).toBe('arrived');
  });
});

/** Minimal in-memory Redis covering the calls the service makes. */
function fakeRedis() {
  const kv = new Map<string, string>();
  const hashes = new Map<string, Record<string, string>>();
  const client = {
    get: async (k: string) => kv.get(k) ?? null,
    incr: async (k: string) => {
      const n = Number(kv.get(k) ?? 0) + 1;
      kv.set(k, String(n));
      return n;
    },
    decr: async (k: string) => {
      const n = Number(kv.get(k) ?? 0) - 1;
      kv.set(k, String(n));
      return n;
    },
    expire: async () => 1,
    pexpireat: async () => 1,
    del: async (k: string) => (hashes.delete(k) || kv.delete(k) ? 1 : 0),
    hset: async (k: string, v: Record<string, unknown>) => {
      const h = hashes.get(k) ?? {};
      for (const [f, x] of Object.entries(v)) h[f] = String(x);
      hashes.set(k, h);
      return 1;
    },
    hgetall: async (k: string) => ({ ...(hashes.get(k) ?? {}) }),
    pipeline() {
      const ops: Array<() => Promise<unknown>> = [];
      const p = {
        hgetall: (k: string) => {
          ops.push(() => client.hgetall(k));
          return p;
        },
        exec: async () => Promise.all(ops.map(async (o) => [null, await o()])),
      };
      return p;
    },
  };
  return { client, hashes };
}

function make(usesPerDay?: string) {
  const redis = fakeRedis();
  const realtime = { emitToUser: jest.fn() };
  const prisma = { driverProfile: { findUnique: jest.fn().mockResolvedValue({ userId: 'd1' }) } };
  const config = {
    get: (k: string) => (k === 'DESTINATION_MODE_USES_PER_DAY' ? usesPerDay : undefined),
  };
  const svc = new DestinationModeService(
    prisma as never,
    redis as never,
    config as never,
    realtime as never,
  );
  const at = (id: string, p: { lat: number; lng: number }) =>
    redis.client.hset(`driver:${id}:loc`, { lat: p.lat, lng: p.lng, ts: Date.now() });
  return { svc, redis, realtime, at };
}

describe('DestinationModeService', () => {
  it('filters only the driver in destination mode; others untouched', async () => {
    const { svc, at } = make();
    await at('d1', DRIVER);
    await at('d2', DRIVER);
    await svc.set('d1', { ...HOME, label: 'Home' });
    const toward = { dropoffLat: TOWARD.lat, dropoffLng: TOWARD.lng };
    const away = { dropoffLat: AWAY.lat, dropoffLng: AWAY.lng };
    expect(await svc.filterCandidates(toward, ['d1', 'd2'])).toEqual(['d1', 'd2']);
    expect(await svc.filterCandidates(away, ['d1', 'd2'])).toEqual(['d2']);
  });

  it('allows DESTINATION_MODE_USES_PER_DAY activations (default 2); moving it is free', async () => {
    const { svc, at } = make();
    await at('d1', DRIVER);
    const r1 = await svc.set('d1', { ...HOME, label: 'Home' });
    expect(r1).toMatchObject({ active: true, usesToday: 1, usesPerDay: 2 });
    // Changing the point while active does not burn a use.
    expect((await svc.set('d1', { ...TOWARD, label: 'Mall' })).usesToday).toBe(1);
    await svc.clear('d1');
    expect((await svc.set('d1', { ...HOME })).usesToday).toBe(2);
    await svc.clear('d1');
    await expect(svc.set('d1', { ...HOME })).rejects.toBeInstanceOf(BadRequestException);
    expect((await svc.get('d1')).usesToday).toBe(2); // the refused try is not counted
  });

  it('honours a configured uses-per-day', async () => {
    const { svc, at } = make('1');
    await at('d1', DRIVER);
    await svc.set('d1', { ...HOME });
    await svc.clear('d1');
    await expect(svc.set('d1', { ...HOME })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('auto-off on arrival: dropped from the mode and back to normal matching', async () => {
    const { svc, at, realtime } = make();
    await at('d1', DRIVER);
    await svc.set('d1', { ...HOME });
    await at('d1', { lat: HOME.lat - 0.002, lng: HOME.lng });
    const away = { dropoffLat: AWAY.lat, dropoffLng: AWAY.lng };
    expect(await svc.filterCandidates(away, ['d1'])).toEqual(['d1']);
    expect((await svc.get('d1')).active).toBe(false);
    expect(realtime.emitToUser).toHaveBeenCalledWith('d1', 'driver:destination_off', {
      reason: 'arrived',
    });
  });

  it('auto-off after 2 h', async () => {
    const { svc, at, redis } = make();
    await at('d1', DRIVER);
    await svc.set('d1', { ...HOME });
    redis.hashes.get(DestinationKeys.active('d1'))!.startedAt = String(
      Date.now() - DESTINATION_MAX_ACTIVE_MS - 1,
    );
    const r = await svc.get('d1');
    expect(r.active).toBe(false);
    expect(r.endedReason).toBe('expired');
  });

  it('refuses a destination the driver is already at', async () => {
    const { svc, at } = make();
    await at('d1', HOME);
    await expect(svc.set('d1', { ...HOME })).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('DispatchService sweep with destination mode', () => {
  it('never offers a trip the destination filter drops', async () => {
    const redis = {
      client: {
        get: jest.fn(async (k: string) => (k.endsWith(':status') ? 'online' : null)),
        smembers: jest.fn().mockResolvedValue([]),
      },
    };
    const prisma = { trip: { findUnique: jest.fn().mockResolvedValue({ status: 'matching' }) } };
    const destination = {
      filterCandidates: jest.fn(async (_t: unknown, ids: string[]) =>
        ids.filter((id) => id !== 'driver-A'),
      ),
    };
    const svc = new DispatchService(
      prisma as never, redis as never, {} as never, {} as never, {} as never,
      {} as never, {} as never, {} as never, {} as never, {} as never,
      {} as never, {} as never, {} as never, undefined, destination as never,
    );
    const internals = svc as unknown as {
      nearestDrivers: jest.Mock;
      rankByRoadEta: jest.Mock;
      offerTo: jest.Mock;
      sweep: (t: unknown, f: Set<string>, r: unknown, d: number, m?: number) => Promise<string>;
    };
    internals.nearestDrivers = jest.fn().mockResolvedValue(['driver-A', 'driver-B']);
    internals.rankByRoadEta = jest.fn(async (_t: unknown, c: string[]) => c);
    internals.offerTo = jest.fn().mockResolvedValue(false);
    const trip = { id: 't1', tier: 'economy', pickupLat: 41.3, pickupLng: 69.24, dropoffLat: 41.22, dropoffLng: 69.24 };
    await internals.sweep(trip, new Set(), { name: 'R', rating: 5 }, Date.now() + 60000);
    expect(internals.offerTo.mock.calls.map((c) => c[0])).toEqual(['driver-B']);
    expect(destination.filterCandidates).toHaveBeenCalled();
  });
});
