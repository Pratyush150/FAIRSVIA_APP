import { RealtimeGateway } from './realtime.gateway';
import { RedisKeys } from '../common/redis/redis.keys';
import { RealtimeService } from './realtime.service';
import { gatewayCors } from './gateway-cors';
import { WsExceptionsFilter } from './ws-exceptions.filter';
import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { WsException } from '@nestjs/websockets';

/**
 * handleDisconnect must evict a dropped/closed driver socket from the matchable
 * pool, keyed off live driver state (driverTier) rather than the JWT role — a
 * driver's token still says 'rider' after onboarding, so a role gate would never
 * fire and dead sockets would leak into dispatch.
 */
describe('RealtimeGateway.handleDisconnect', () => {
  function makeGateway(redisState: Record<string, string | null>) {
    const goOffline = jest.fn(async (userId: string, tier: string | null) => {
      // Mirrors DriversService.forceOffline's own mid-trip guard.
      if (redisState[RedisKeys.driverActiveTrip(userId)]) return false;
      return true;
    });
    const redis = {
      client: {
        get: jest.fn((key: string) => Promise.resolve(redisState[key] ?? null)),
      },
    };
    const drivers = { forceOffline: goOffline };
    // Only redis + drivers are used by handleDisconnect; the rest are unused.
    const gateway = new RealtimeGateway(
      null as never, // jwt
      null as never, // config
      null as never, // realtime
      redis as never,
      null as never, // location
      null as never, // dispatch
      null as never, // trips
      drivers as never,
      null as never, // chat
      null as never, // prisma,
      { touch: jest.fn() } as never,
    );
    return { gateway, goOffline };
  }

  const client = (userId?: string, role = 'rider') =>
    ({ data: { userId, role } }) as never;

  it('evicts an online driver even though the JWT role is "rider"', async () => {
    const { gateway, goOffline } = makeGateway({
      [RedisKeys.driverTier('d1')]: 'economy',
      [RedisKeys.driverActiveTrip('d1')]: null,
    });
    await gateway.handleDisconnect(client('d1', 'rider'));
    // Server-initiated → forceOffline (DB sync + driver:status_changed), with
    // the reason the app can show.
    expect(goOffline).toHaveBeenCalledWith('d1', 'economy', 'disconnect');
  });

  it('does nothing for a non-driver (no driverTier)', async () => {
    const { gateway, goOffline } = makeGateway({});
    await gateway.handleDisconnect(client('u1', 'rider'));
    expect(goOffline).not.toHaveBeenCalled();
  });

  it('keeps a mid-trip driver in place so they can reconnect', async () => {
    const { gateway, goOffline } = makeGateway({
      [RedisKeys.driverTier('d2')]: 'economy',
      [RedisKeys.driverActiveTrip('d2')]: 'trip-9',
    });
    await gateway.handleDisconnect(client('d2', 'rider'));
    // forceOffline is asked but declines (mid-trip guard) — nothing flips.
    await expect(goOffline.mock.results[0].value).resolves.toBe(false);
  });

  it('ignores an unauthenticated socket', async () => {
    const { gateway, goOffline } = makeGateway({});
    await gateway.handleDisconnect(client(undefined));
    expect(goOffline).not.toHaveBeenCalled();
  });
});

describe('RealtimeGateway.handleConnection', () => {
  function makeGateway(
    user: { id: string; role: string; isActive: boolean } | null,
    opts: { profileStatus?: string | null; redisStatus?: string | null } = {},
  ) {
    const findUnique = jest.fn().mockResolvedValue(user);
    const profileFind = jest.fn().mockResolvedValue(
      opts.profileStatus === undefined
        ? null
        : opts.profileStatus === null
          ? null
          : { status: opts.profileStatus },
    );
    const profileUpdate = jest.fn().mockResolvedValue({ count: 1 });
    const redis = { client: { get: jest.fn().mockResolvedValue(opts.redisStatus ?? null) } };
    const gateway = new RealtimeGateway(
      { verifyAsync: jest.fn().mockResolvedValue({ sub: 'u1', role: 'rider' }) } as never,
      { get: () => ({ accessSecret: 's' }) } as never,
      null as never, // realtime
      redis as never,
      null as never, // location
      null as never, // dispatch
      null as never, // trips
      null as never, // drivers
      null as never, // chat
      {
        user: { findUnique },
        driverProfile: { findUnique: profileFind, updateMany: profileUpdate },
      } as never,
      { touch: jest.fn() } as never,
    );
    const client = {
      data: {} as { userId?: string; role?: string },
      handshake: { auth: { token: 'jwt' }, headers: {} },
      join: jest.fn().mockResolvedValue(undefined),
      emit: jest.fn(),
      disconnect: jest.fn(),
    };
    return { gateway, client, findUnique, profileFind, profileUpdate };
  }

  // A message that arrives while handleConnection is still verifying the JWT
  // must wait for it, not be dropped because client.data.userId is unset yet.
  it('a message racing the async auth waits for it instead of being dropped', async () => {
    const { gateway, client, findUnique } = makeGateway({ id: 'u1', role: 'rider', isActive: true });
    let release!: () => void;
    findUnique.mockReturnValue(new Promise((r) => (release = () => r({ id: 'u1', role: 'rider', isActive: true }))));
    const getTrip = jest.fn().mockResolvedValue({ id: 't1' });
    (gateway as unknown as { trips: unknown }).trips = { getTrip };

    const connecting = gateway.handleConnection(client as never);
    const racing = gateway.onSync(client as never, { tripId: 't1' }); // emitted "immediately after connect"
    await new Promise((r) => setImmediate(r));
    expect(getTrip).not.toHaveBeenCalled(); // still waiting on auth
    release();
    await Promise.all([connecting, racing]);
    expect(getTrip).toHaveBeenCalledWith('u1', 't1');
    expect(client.emit).toHaveBeenCalledWith('trip:sync', { id: 't1' });
  });

  // Presence sync on (re)connect — closes the "app shows Online, server says
  // offline, riders get no_drivers" gap. The server never silently re-adds
  // the driver; it tells the app and fixes a drifted DB row.
  describe('driver presence sync', () => {
    it('tells a reconnecting driver they are offline and repairs a DB row stuck at online', async () => {
      const { gateway, client, profileUpdate } = makeGateway(
        { id: 'u1', role: 'driver', isActive: true },
        { profileStatus: 'online', redisStatus: null },
      );
      await gateway.handleConnection(client as never);
      expect(profileUpdate).toHaveBeenCalledWith({
        where: { userId: 'u1', status: 'online' },
        data: { status: 'offline' },
      });
      expect(client.emit).toHaveBeenCalledWith('driver:status_changed', {
        status: 'offline',
        reason: 'presence_lost',
      });
    });

    it('confirms a live presence without touching the DB', async () => {
      const { gateway, client, profileUpdate } = makeGateway(
        { id: 'u1', role: 'driver', isActive: true },
        { profileStatus: 'online', redisStatus: 'on_trip' },
      );
      await gateway.handleConnection(client as never);
      expect(profileUpdate).not.toHaveBeenCalled();
      expect(client.emit).toHaveBeenCalledWith('driver:status_changed', {
        status: 'on_trip',
        reason: 'sync',
      });
    });

    it('sends a plain sync (not presence_lost) when both sides already say offline', async () => {
      const { gateway, client, profileUpdate } = makeGateway(
        { id: 'u1', role: 'driver', isActive: true },
        { profileStatus: 'offline', redisStatus: 'offline' },
      );
      await gateway.handleConnection(client as never);
      expect(profileUpdate).not.toHaveBeenCalled();
      expect(client.emit).toHaveBeenCalledWith('driver:status_changed', {
        status: 'offline',
        reason: 'sync',
      });
    });

    it('does nothing for riders', async () => {
      const { gateway, client, profileFind } = makeGateway({ id: 'u1', role: 'rider', isActive: true });
      await gateway.handleConnection(client as never);
      expect(profileFind).not.toHaveBeenCalled();
      expect(client.emit).not.toHaveBeenCalled();
    });

    it('a presence-sync failure never rejects the connection', async () => {
      const { gateway, client, profileFind } = makeGateway({ id: 'u1', role: 'driver', isActive: true });
      profileFind.mockRejectedValue(new Error('db down'));
      await gateway.handleConnection(client as never);
      expect(client.disconnect).not.toHaveBeenCalled();
      expect(client.data.userId).toBe('u1');
    });
  });

  it('admits an active user and takes the role from the DB, not the token', async () => {
    const { gateway, client } = makeGateway({ id: 'u1', role: 'driver', isActive: true });
    await gateway.handleConnection(client as never);
    expect(client.data).toEqual({ userId: 'u1', role: 'driver' });
    expect(client.join).toHaveBeenCalledWith('user:u1');
    expect(client.disconnect).not.toHaveBeenCalled();
  });

  it('rejects a deactivated user even though the JWT signature is valid', async () => {
    const { gateway, client } = makeGateway({ id: 'u1', role: 'rider', isActive: false });
    await gateway.handleConnection(client as never);
    expect(client.data.userId).toBeUndefined();
    expect(client.emit).toHaveBeenCalledWith('error', { message: 'unauthorized' });
    expect(client.disconnect).toHaveBeenCalledWith(true);
  });

  it('rejects a token for a user that no longer exists', async () => {
    const { gateway, client } = makeGateway(null);
    await gateway.handleConnection(client as never);
    expect(client.join).not.toHaveBeenCalled();
    expect(client.disconnect).toHaveBeenCalledWith(true);
  });
});

describe('RealtimeService.disconnectUser', () => {
  it('force-closes every socket in the user room', () => {
    const disconnectSockets = jest.fn();
    const server = { in: jest.fn(() => ({ disconnectSockets })) };
    const svc = new RealtimeService();
    svc.setServer(server as never);
    svc.disconnectUser('u9');
    expect(server.in).toHaveBeenCalledWith('user:u9');
    expect(disconnectSockets).toHaveBeenCalledWith(true);
  });

  it('is a no-op before the server is attached', () => {
    expect(() => new RealtimeService().disconnectUser('u9')).not.toThrow();
  });
});

describe('gatewayCors', () => {
  it('reflects any origin outside production', () => {
    expect(gatewayCors({ NODE_ENV: 'development' })).toEqual({ origin: true, credentials: true });
  });

  it('uses the CORS_ORIGINS allow-list in production', () => {
    expect(
      gatewayCors({ NODE_ENV: 'production', CORS_ORIGINS: 'https://a.com, https://b.com,' }),
    ).toEqual({ origin: ['https://a.com', 'https://b.com'], credentials: true });
  });

  it('allows no browser origin in production when the list is empty', () => {
    expect(gatewayCors({ NODE_ENV: 'production' }).origin).toBe(false);
  });
});

/**
 * WS error surfacing: an HttpException thrown inside a @SubscribeMessage
 * handler used to reach the client as `{ message: 'Internal server error' }`,
 * hiding e.g. "Finish your current trip before going offline.".
 */
describe('WsExceptionsFilter', () => {
  function run(exception: unknown, pattern = 'driver:status') {
    const emit = jest.fn();
    const host = {
      switchToWs: () => ({ getClient: () => ({ emit }), getPattern: () => pattern }),
    };
    new WsExceptionsFilter().catch(exception, host as never);
    return emit;
  }

  it('forwards an HttpException message and status to the client', () => {
    const emit = run(new BadRequestException('Finish your current trip before going offline.'));
    expect(emit).toHaveBeenCalledWith('exception', {
      status: 'error',
      code: 400,
      message: 'Finish your current trip before going offline.',
      event: 'driver:status',
    });
  });

  it('joins class-validator message arrays', () => {
    const emit = run(new BadRequestException(['lat must not be greater than 90', 'lng must be a number']));
    expect(emit.mock.calls[0][1]).toMatchObject({
      code: 400,
      message: 'lat must not be greater than 90; lng must be a number',
    });
  });

  it('keeps the HTTP status of other exceptions (403)', () => {
    const emit = run(new ForbiddenException('Documents are not verified yet'));
    expect(emit.mock.calls[0][1]).toMatchObject({ code: 403, message: 'Documents are not verified yet' });
  });

  it('passes a WsException through', () => {
    const emit = run(new WsException('nope'));
    expect(emit.mock.calls[0][1]).toMatchObject({ code: 400, message: 'nope' });
  });

  it('still masks unexpected errors as a generic 500', () => {
    const emit = run(new Error('ECONNRESET redis://internal-host'));
    expect(emit.mock.calls[0][1]).toEqual({
      status: 'error',
      code: 500,
      message: 'Internal server error',
      event: 'driver:status',
    });
  });
});
