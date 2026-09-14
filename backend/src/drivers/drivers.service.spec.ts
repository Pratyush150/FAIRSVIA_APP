import { DriversService } from './drivers.service';

/**
 * Onboarding re-verification: a verified driver who changes plate/licence must
 * drop back to pending unless DRIVER_AUTO_VERIFY (dev-only) is on.
 */
describe('DriversService.onboarding', () => {
  const dto = {
    vehicleMake: 'Toyota',
    vehicleModel: 'Prius',
    vehicleColor: 'white',
    plateNumber: 'ABC123',
    vehicleTier: 'economy',
    licenseNo: 'LIC-1',
  };

  function make(
    existing: { docsVerified: boolean; plateNumber: string | null; licenseNo: string | null } | null,
    autoVerify: boolean,
  ) {
    const prisma = {
      driverProfile: {
        findUnique: jest.fn().mockResolvedValue(existing),
        upsert: jest.fn(async ({ update }: { update: object }) => ({ ...update })),
      },
      user: { update: jest.fn().mockResolvedValue({}) },
    };
    const config = { get: jest.fn(() => autoVerify) };
    const svc = new DriversService(
      prisma as never,
      {} as never,
      config as never,
      { emitToUser: jest.fn() } as never,
    );
    return { svc, prisma };
  }

  const updateArg = (prisma: { driverProfile: { upsert: jest.Mock } }) =>
    prisma.driverProfile.upsert.mock.calls[0][0].update as Record<string, unknown>;
  const createArg = (prisma: { driverProfile: { upsert: jest.Mock } }) =>
    prisma.driverProfile.upsert.mock.calls[0][0].create as Record<string, unknown>;

  it('first onboarding is pending when auto-verify is off, approved when on', async () => {
    const off = make(null, false);
    await off.svc.onboarding('d1', dto);
    expect(createArg(off.prisma).docsVerified).toBe(false);

    const on = make(null, true);
    await on.svc.onboarding('d1', dto);
    expect(createArg(on.prisma).docsVerified).toBe(true);
  });

  it('a verified driver changing the plate is reset to unverified', async () => {
    const { svc, prisma } = make(
      { docsVerified: true, plateNumber: 'OLD999', licenseNo: 'LIC-1' },
      false,
    );
    await svc.onboarding('d1', dto);
    expect(updateArg(prisma).docsVerified).toBe(false);
  });

  it('a verified driver changing the licence is reset to unverified', async () => {
    const { svc, prisma } = make(
      { docsVerified: true, plateNumber: 'ABC123', licenseNo: 'LIC-0' },
      false,
    );
    await svc.onboarding('d1', dto);
    expect(updateArg(prisma).docsVerified).toBe(false);
  });

  it('re-submitting with the same identity fields keeps the verification', async () => {
    const { svc, prisma } = make(
      { docsVerified: true, plateNumber: 'ABC123', licenseNo: 'LIC-1' },
      false,
    );
    await svc.onboarding('d1', { ...dto, vehicleColor: 'black', vehicleModel: 'Camry' });
    expect(updateArg(prisma)).not.toHaveProperty('docsVerified');
  });

  it('an unverified driver changing the plate stays as-is (nothing to reset)', async () => {
    const { svc, prisma } = make(
      { docsVerified: false, plateNumber: 'OLD999', licenseNo: null },
      false,
    );
    await svc.onboarding('d1', dto);
    expect(updateArg(prisma)).not.toHaveProperty('docsVerified');
  });

  it('DRIVER_AUTO_VERIFY keeps a verified driver verified across a plate change', async () => {
    const { svc, prisma } = make(
      { docsVerified: true, plateNumber: 'OLD999', licenseNo: 'LIC-1' },
      true,
    );
    await svc.onboarding('d1', dto);
    expect(updateArg(prisma)).not.toHaveProperty('docsVerified');
  });
});

/**
 * Server-initiated offline (socket drop / stale GPS): must clear presence,
 * keep the DB profile in step, and tell the app — but never mid-trip.
 */
describe('DriversService.forceOffline', () => {
  function make(state: Record<string, string | null>) {
    const client = {
      get: jest.fn(async (k: string) => state[k] ?? null),
      set: jest.fn().mockResolvedValue('OK'),
      zrem: jest.fn().mockResolvedValue(1),
      del: jest.fn().mockResolvedValue(1),
    };
    const prisma = {
      driverProfile: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
    };
    const realtime = { emitToUser: jest.fn() };
    const svc = new DriversService(
      prisma as never,
      { client } as never,
      { get: jest.fn() } as never,
      realtime as never,
    );
    return { svc, client, prisma, realtime };
  }

  it('flips Redis + DB offline and emits driver:status_changed with the reason', async () => {
    const { svc, client, prisma, realtime } = make({});
    await expect(svc.forceOffline('d1', 'economy', 'disconnect')).resolves.toBe(true);
    expect(client.set).toHaveBeenCalledWith('driver:d1:status', 'offline');
    expect(client.zrem).toHaveBeenCalledWith('drivers:geo:economy', 'd1');
    expect(prisma.driverProfile.updateMany).toHaveBeenCalledWith({
      where: { userId: 'd1', status: 'online' },
      data: { status: 'offline' },
    });
    expect(realtime.emitToUser).toHaveBeenCalledWith('d1', 'driver:status_changed', {
      status: 'offline',
      reason: 'disconnect',
    });
  });

  it('refuses to touch a driver who is mid-trip', async () => {
    const { svc, client, prisma, realtime } = make({ 'driver:d1:activeTrip': 'trip-9' });
    await expect(svc.forceOffline('d1', 'economy', 'stale_location')).resolves.toBe(false);
    expect(client.set).not.toHaveBeenCalled();
    expect(prisma.driverProfile.updateMany).not.toHaveBeenCalled();
    expect(realtime.emitToUser).not.toHaveBeenCalled();
  });

  it('resolves the tier from Redis when the caller does not know it', async () => {
    const { svc, client } = make({ 'driver:d1:tier': 'xl' });
    await svc.forceOffline('d1', null, 'presence_lost');
    expect(client.zrem).toHaveBeenCalledWith('drivers:geo:xl', 'd1');
  });

  it('survives a DB write failure (presence is still cleared and the app told)', async () => {
    const { svc, prisma, realtime } = make({});
    prisma.driverProfile.updateMany.mockRejectedValue(new Error('db down'));
    await expect(svc.forceOffline('d1', 'economy', 'disconnect')).resolves.toBe(true);
    expect(realtime.emitToUser).toHaveBeenCalled();
  });
});

describe('DriversService.getProfileWithPresence', () => {
  function make(dbStatus: string, liveStatus: string | null) {
    const prisma = {
      driverProfile: {
        findUnique: jest.fn().mockResolvedValue({ userId: 'd1', status: dbStatus, docsVerified: true }),
      },
    };
    const redis = { client: { get: jest.fn().mockResolvedValue(liveStatus) } };
    const svc = new DriversService(
      prisma as never,
      redis as never,
      { get: jest.fn() } as never,
      { emitToUser: jest.fn() } as never,
    );
    return { svc, redis };
  }

  it('reports the live (Redis) presence over the stored column', async () => {
    const { svc, redis } = make('online', 'offline');
    const me = await svc.getProfileWithPresence('d1');
    expect(me.status).toBe('offline');
    expect(redis.client.get).toHaveBeenCalledWith('driver:d1:status');
  });

  it('falls back to the stored status when Redis has no entry', async () => {
    const { svc } = make('online', null);
    expect((await svc.getProfileWithPresence('d1')).status).toBe('online');
  });
});
