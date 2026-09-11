import { ForbiddenException, HttpException } from '@nestjs/common';
import { ChatService, POST_COMPLETION_GRACE_MS } from './chat.service';

describe('ChatService', () => {
  let counters: Map<string, number>;
  let lists: Map<string, string[]>;
  let expireCalls: string[];

  const trip = {
    riderId: 'rider-1',
    driverId: 'driver-1',
    status: 'accepted',
    completedAt: null as Date | null,
  };
  const prisma = { trip: { findUnique: jest.fn(async () => trip) } };
  const redis = {
    incrWithTtl: jest.fn(async (k: string) => {
      const n = (counters.get(k) ?? 0) + 1;
      counters.set(k, n);
      return n;
    }),
    client: {
      rpush: jest.fn(async (k: string, v: string) => {
        const l = lists.get(k) ?? [];
        l.push(v);
        lists.set(k, l);
        return l.length;
      }),
      ltrim: jest.fn(async () => 'OK'),
      expire: jest.fn(async (k: string) => {
        expireCalls.push(k);
        return 1;
      }),
      lrange: jest.fn(async (k: string) => lists.get(k) ?? []),
    },
  };
  const realtime = { emitToUser: jest.fn() };
  let service: ChatService;

  beforeEach(() => {
    counters = new Map();
    lists = new Map();
    expireCalls = [];
    trip.status = 'accepted';
    trip.completedAt = null;
    jest.clearAllMocks();
    service = new ChatService(prisma as never, redis as never, realtime as never);
  });

  it('posts a message to both parties while the trip is active', async () => {
    const msg = await service.postMessage('rider-1', 't1', ' hi ');
    expect(msg.text).toBe('hi');
    expect(realtime.emitToUser).toHaveBeenCalledWith('rider-1', 'trip:message', msg);
    expect(realtime.emitToUser).toHaveBeenCalledWith('driver-1', 'trip:message', msg);
  });

  it('sets the 24h TTL only when the thread is created, not on every post', async () => {
    await service.postMessage('rider-1', 't1', 'one');
    await service.postMessage('driver-1', 't1', 'two');
    await service.postMessage('rider-1', 't1', 'three');
    expect(expireCalls).toEqual(['trip:t1:chat']);
  });

  it.each(['requested', 'matching', 'cancelled', 'no_drivers', 'expired', 'scheduled'])(
    'refuses to post while the trip is %s',
    async (status) => {
      trip.status = status;
      await expect(service.postMessage('rider-1', 't1', 'hi')).rejects.toBeInstanceOf(
        ForbiddenException,
      );
      expect(redis.client.rpush).not.toHaveBeenCalled();
    },
  );

  it('allows posting for 15 minutes after completion, then closes', async () => {
    trip.status = 'completed';
    trip.completedAt = new Date(Date.now() - POST_COMPLETION_GRACE_MS + 5_000);
    await expect(service.postMessage('driver-1', 't1', 'left a bag?')).resolves.toBeDefined();

    trip.completedAt = new Date(Date.now() - POST_COMPLETION_GRACE_MS - 5_000);
    await expect(service.postMessage('driver-1', 't1', 'still there?')).rejects.toThrow(
      /chat is closed/i,
    );
  });

  it('rate-limits a sender to 10 messages per window (429)', async () => {
    for (let i = 0; i < 10; i++) {
      await service.postMessage('rider-1', 't1', `m${i}`);
    }
    const err = await service.postMessage('rider-1', 't1', 'm10').catch((e) => e);
    expect(err).toBeInstanceOf(HttpException);
    expect((err as HttpException).getStatus()).toBe(429);
    // The other participant has their own bucket.
    await expect(service.postMessage('driver-1', 't1', 'ok')).resolves.toBeDefined();
  });

  it('history stays readable after the chat is closed', async () => {
    await service.postMessage('rider-1', 't1', 'hello');
    trip.status = 'cancelled';
    const h = await service.history('rider-1', 't1');
    expect(h.map((m) => m.text)).toEqual(['hello']);
  });

  it('rejects non-participants', async () => {
    await expect(service.postMessage('stranger', 't1', 'hi')).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });
});
