import { TripStatus } from '@prisma/client';
import { ForbiddenException, ConflictException, NotFoundException } from '@nestjs/common';
import { firstName, placeLabel, publicStatus, ShareService, TOKEN_RE } from './share.service';

describe('share helpers', () => {
  it('keeps only the place name of an address', () => {
    expect(placeLabel('Chorsu Bazaar, Navoi St, Tashkent, Uzbekistan')).toBe('Chorsu Bazaar');
    expect(placeLabel('12, Navoi St, Tashkent')).toBe('12, Navoi St');
    expect(placeLabel(null)).toBeNull();
    expect(placeLabel('  ,  ')).toBeNull();
  });
  it('first name only', () => {
    expect(firstName('Bekzod Tursunov')).toBe('Bekzod');
    expect(firstName('  ')).toBeNull();
    expect(firstName(null)).toBeNull();
  });
  it('maps internal statuses to the public vocabulary', () => {
    expect(publicStatus(TripStatus.matching)).toBe('finding_driver');
    expect(publicStatus(TripStatus.accepted)).toBe('driver_on_the_way');
    expect(publicStatus(TripStatus.arrived)).toBe('driver_arrived');
    expect(publicStatus(TripStatus.in_progress)).toBe('on_trip');
    expect(publicStatus(TripStatus.completed)).toBe('completed');
    expect(publicStatus(TripStatus.cancelled)).toBe('ended');
  });
});

describe('ShareService', () => {
  const store = new Map<string, string>();
  const redis = {
    get: jest.fn(async (k: string) => store.get(k) ?? null),
    del: jest.fn(async (k: string) => void store.delete(k)),
    client: {
      multi: () => {
        const ops: [string, string][] = [];
        const m = {
          set: (k: string, v: string) => (ops.push([k, v]), m),
          exec: async () => ops.forEach(([k, v]) => store.set(k, v)),
        };
        return m;
      },
      ttl: jest.fn(async () => 43200),
    },
  };
  const trip = { riderId: 'r1', status: TripStatus.accepted as TripStatus };
  const prisma = { trip: { findUnique: jest.fn(async () => trip) } };
  const config = { get: jest.fn(() => undefined as string | undefined) };
  const svc = new ShareService(prisma as never, redis as never, config as never);

  beforeEach(() => {
    store.clear();
    trip.status = TripStatus.accepted;
    config.get.mockReturnValue(undefined);
  });

  it('mints a 192-bit url-safe token and a url on the request origin', async () => {
    const res = await svc.createLink('r1', 't1', 'https://x.trycloudflare.com');
    expect(res.token).toMatch(TOKEN_RE);
    expect(Buffer.from(res.token, 'base64url')).toHaveLength(24);
    expect(res.url).toBe(`https://x.trycloudflare.com/api/v1/public/t/${res.token}`);
  });

  it('PUBLIC_BASE_URL wins over the request origin', async () => {
    config.get.mockReturnValue('https://track.ridevela.app/');
    const res = await svc.createLink('r1', 't1', 'http://192.168.1.69:3000');
    expect(res.url.startsWith('https://track.ridevela.app/api/v1/public/t/')).toBe(true);
  });

  it('refuses anyone but the rider, and ended trips', async () => {
    await expect(svc.createLink('someone', 't1', 'http://h')).rejects.toBeInstanceOf(ForbiddenException);
    trip.status = TripStatus.cancelled;
    await expect(svc.createLink('r1', 't1', 'http://h')).rejects.toBeInstanceOf(ConflictException);
  });

  it('unknown or malformed tokens are 404 without touching the DB', async () => {
    prisma.trip.findUnique.mockClear();
    await expect(svc.track('bad token')).rejects.toBeInstanceOf(NotFoundException);
    await expect(svc.track('A'.repeat(32))).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.trip.findUnique).not.toHaveBeenCalled();
  });
});
