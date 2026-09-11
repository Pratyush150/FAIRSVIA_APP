import { RealtimeGateway } from './realtime.gateway';
import { RedisKeys } from '../common/redis/redis.keys';
import { RealtimeService } from './realtime.service';
import { gatewayCors } from './gateway-cors';

/**
 * handleDisconnect must evict a dropped/closed driver socket from the matchable
 * pool, keyed off live driver state (driverTier) rather than the JWT role — a
 * driver's token still says 'rider' after onboarding, so a role gate would never
 * fire and dead sockets would leak into dispatch.
 */
describe('RealtimeGateway.handleDisconnect', () => {
  function makeGateway(redisState: Record<string, string | null>) {
    const goOffline = jest.fn().mockResolvedValue(undefined);
    const redis = {
      client: {
        get: jest.fn((key: string) => Promise.resolve(redisState[key] ?? null)),
      },
    };
    const drivers = { goOffline };
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
      null as never, // prisma
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
    expect(goOffline).toHaveBeenCalledWith('d1', 'economy');
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
    expect(goOffline).not.toHaveBeenCalled();
  });

  it('ignores an unauthenticated socket', async () => {
    const { gateway, goOffline } = makeGateway({});
    await gateway.handleDisconnect(client(undefined));
    expect(goOffline).not.toHaveBeenCalled();
  });
});

describe('RealtimeGateway.handleConnection', () => {
  function makeGateway(user: { id: string; role: string; isActive: boolean } | null) {
    const findUnique = jest.fn().mockResolvedValue(user);
    const gateway = new RealtimeGateway(
      { verifyAsync: jest.fn().mockResolvedValue({ sub: 'u1', role: 'rider' }) } as never,
      { get: () => ({ accessSecret: 's' }) } as never,
      null as never, // realtime
      null as never, // redis
      null as never, // location
      null as never, // dispatch
      null as never, // trips
      null as never, // drivers
      null as never, // chat
      { user: { findUnique } } as never,
    );
    const client = {
      data: {} as { userId?: string; role?: string },
      handshake: { auth: { token: 'jwt' }, headers: {} },
      join: jest.fn().mockResolvedValue(undefined),
      emit: jest.fn(),
      disconnect: jest.fn(),
    };
    return { gateway, client, findUnique };
  }

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
