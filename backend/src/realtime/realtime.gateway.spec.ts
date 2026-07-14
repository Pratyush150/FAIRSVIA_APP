import { RealtimeGateway } from './realtime.gateway';
import { RedisKeys } from '../common/redis/redis.keys';

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
