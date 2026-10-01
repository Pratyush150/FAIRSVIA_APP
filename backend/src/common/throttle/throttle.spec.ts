import { ExecutionContext } from '@nestjs/common';
import { AppThrottlerGuard } from './app-throttler.guard';
import { RedisThrottlerStorage } from './redis-throttler.storage';
import { bucketFor, classifyRoute, throttleConfig } from './throttle.config';

describe('throttleConfig', () => {
  it('is disabled under jest (NODE_ENV=test) regardless of other flags', () => {
    expect(throttleConfig({ NODE_ENV: 'test' }).disabled).toBe(true);
  });

  it('is enabled in dev/prod by default with the documented limits', () => {
    const cfg = throttleConfig({ NODE_ENV: 'production' });
    expect(cfg).toEqual({
      disabled: false,
      ttlMs: 60_000,
      defaultLimit: 120,
      tightLimit: 5,
      moderateLimit: 30,
    });
  });

  it('honours THROTTLE_DISABLED and numeric overrides', () => {
    expect(throttleConfig({ NODE_ENV: 'development', THROTTLE_DISABLED: 'true' }).disabled).toBe(true);
    expect(throttleConfig({ NODE_ENV: 'development', THROTTLE_DISABLED: '1' }).disabled).toBe(true);
    const cfg = throttleConfig({
      NODE_ENV: 'development',
      THROTTLE_LIMIT: '1000',
      THROTTLE_TIGHT_LIMIT: '50',
      THROTTLE_MODERATE_LIMIT: 'garbage',
    });
    expect(cfg.defaultLimit).toBe(1000);
    expect(cfg.tightLimit).toBe(50);
    expect(cfg.moderateLimit).toBe(30); // invalid value falls back
  });
});

describe('classifyRoute', () => {
  it.each([
    ['POST', '/api/v1/auth/otp/request', 'tight'],
    ['POST', '/api/v1/auth/refresh', 'tight'],
    ['POST', '/api/v1/trips/estimate', 'moderate'],
    ['GET', '/api/v1/places/autocomplete', 'moderate'],
    ['GET', '/api/v1/places/details', 'moderate'],
    ['GET', '/api/v1/places/reverse', 'moderate'],
    ['POST', '/api/v1/trips/:tripId/messages', 'moderate'],
    ['POST', '/api/v1/support/tickets', 'moderate'],
  ])('%s %s -> %s', (method, path, bucket) => {
    expect(classifyRoute(method, path)).toBe(bucket);
  });

  it.each([
    ['POST', '/api/v1/auth/otp/verify'],
    ['GET', '/api/v1/trips/:tripId/messages'], // reading history is not throttled tightly
    ['POST', '/api/v1/trips'],
    ['GET', '/api/v1/support/tickets'],
    ['POST', '/api/v1/support/tickets/:id/messages'],
    ['GET', '/api/v1/health'],
    ['GET', '/metrics'],
  ])('%s %s -> default only', (method, path) => {
    expect(classifyRoute(method, path)).toBeNull();
  });

  it('is prefix-agnostic (works with or without /api/vN)', () => {
    expect(classifyRoute('post', '/auth/otp/request')).toBe('tight');
    expect(classifyRoute('POST', '/api/v2/auth/otp/request')).toBe('tight');
  });
});

function httpContext(req: Record<string, unknown>, type = 'http'): ExecutionContext {
  return {
    getType: () => type,
    switchToHttp: () => ({ getRequest: () => req, getResponse: () => ({}) }),
    getHandler: () => function handler() {},
    getClass: () => class Ctl {},
  } as unknown as ExecutionContext;
}

describe('bucketFor', () => {
  it('uses the Express route pattern when present', () => {
    const ctx = httpContext({
      method: 'POST',
      route: { path: '/api/v1/trips/:tripId/messages' },
      path: '/api/v1/trips/0b1c/messages',
    });
    expect(bucketFor(ctx)).toBe('moderate');
  });

  it('returns null for non-HTTP (websocket) contexts', () => {
    expect(bucketFor(httpContext({ method: 'POST' }, 'ws'))).toBeNull();
  });
});

describe('AppThrottlerGuard', () => {
  it('skips every context when disabled, and non-HTTP contexts always', async () => {
    // State the precondition rather than inherit it. The guard reads
    // `disabled` from the environment at construction, and this test used to
    // rely on jest defaulting NODE_ENV to 'test'. Jest only does that when
    // NODE_ENV is unset — the dev container pins it to 'development', so
    // `make test-backend` failed here while CI (where it is unset) passed.
    // A test whose result depends on where it runs is not a test.
    const prev = process.env.THROTTLE_DISABLED;
    process.env.THROTTLE_DISABLED = 'true';
    try {
      const guard = new AppThrottlerGuard(
        { throttlers: [{ ttl: 60_000, limit: 1 }] },
        { increment: jest.fn() } as never,
        { getAllAndOverride: jest.fn() } as never,
      );
      await guard.onModuleInit();
      // Disabled → canActivate never touches storage.
      await expect(guard.canActivate(httpContext({ ip: '1.2.3.4', headers: {} }))).resolves.toBe(true);
      await expect(guard.canActivate(httpContext({}, 'ws'))).resolves.toBe(true);
    } finally {
      if (prev === undefined) delete process.env.THROTTLE_DISABLED;
      else process.env.THROTTLE_DISABLED = prev;
    }
  });

  it('tracks by req.ip', async () => {
    const guard = new AppThrottlerGuard(
      { throttlers: [] },
      { increment: jest.fn() } as never,
      { getAllAndOverride: jest.fn() } as never,
    );
    // protected → reach through for the unit test
    const tracker = await (guard as unknown as { getTracker(r: object): Promise<string> })
      .getTracker({ ip: '10.0.0.7' });
    expect(tracker).toBe('10.0.0.7');
  });
});

describe('RedisThrottlerStorage', () => {
  it('maps the Lua reply (ms) to the throttler record (s) and namespaces keys', async () => {
    const evalFn = jest.fn().mockResolvedValue([3, 59_400, 0, 0]);
    const storage = new RedisThrottlerStorage({ eval: evalFn } as never);
    const rec = await storage.increment('abc', 60_000, 5, 60_000, 'tight');
    expect(rec).toEqual({ totalHits: 3, timeToExpire: 60, isBlocked: false, timeToBlockExpire: 0 });
    const args = evalFn.mock.calls[0];
    expect(args[1]).toBe(2);
    expect(args[2]).toBe('throttle:tight:abc');
    expect(args[3]).toBe('throttle:tight:abc:block');
    expect(args.slice(4)).toEqual(['60000', '5', '60000']);
  });

  it('reports a block with the remaining block time', async () => {
    const storage = new RedisThrottlerStorage({
      eval: jest.fn().mockResolvedValue([6, 10_000, 1, 42_000]),
    } as never);
    const rec = await storage.increment('k', 60_000, 5, 60_000, 'tight');
    expect(rec.isBlocked).toBe(true);
    expect(rec.timeToBlockExpire).toBe(42);
  });

  it('fails open when Redis is unavailable', async () => {
    const storage = new RedisThrottlerStorage({
      eval: jest.fn().mockRejectedValue(new Error('ECONNREFUSED')),
    } as never);
    const rec = await storage.increment('k', 60_000, 5, 60_000, 'default');
    expect(rec.isBlocked).toBe(false);
  });
});
