import { NotificationsService } from './notifications.service';
import { PushProvider, StalePushTokenError } from './push-provider.interface';
import { ConflictException } from '@nestjs/common';
import { NOTIFY_JOB } from '../common/queue/queue.constants';

describe('NotificationsService', () => {
  function makeProvider() {
    return { send: jest.fn().mockResolvedValue(undefined) } as PushProvider;
  }
  function makeQueue() {
    return { add: jest.fn().mockResolvedValue({}) } as never;
  }

  it('registers a new device via upsert (never re-assigns the owner)', async () => {
    const prisma = {
      deviceToken: {
        findUnique: jest.fn().mockResolvedValue(null),
        upsert: jest.fn().mockResolvedValue({}),
      },
    } as never;
    const svc = new NotificationsService(prisma, makeProvider(), makeQueue());

    await svc.register('u1', 'tok-1', 'ios');

    expect((prisma as any).deviceToken.upsert).toHaveBeenCalledWith({
      where: { token: 'tok-1' },
      create: { userId: 'u1', token: 'tok-1', platform: 'ios' },
      update: { platform: 'ios' },
    });
  });

  it('re-registering your own token just refreshes it', async () => {
    const prisma = {
      deviceToken: {
        findUnique: jest.fn().mockResolvedValue({ userId: 'u1' }),
        upsert: jest.fn().mockResolvedValue({}),
      },
    } as never;
    const svc = new NotificationsService(prisma, makeProvider(), makeQueue());
    await expect(svc.register('u1', 'tok-1', 'android')).resolves.toEqual({ ok: true });
    expect((prisma as any).deviceToken.upsert).toHaveBeenCalledTimes(1);
  });

  it('rejects (409) a token that belongs to another user', async () => {
    const prisma = {
      deviceToken: {
        findUnique: jest.fn().mockResolvedValue({ userId: 'victim' }),
        upsert: jest.fn(),
      },
    } as never;
    const svc = new NotificationsService(prisma, makeProvider(), makeQueue());
    await expect(svc.register('attacker', 'tok-1')).rejects.toBeInstanceOf(
      ConflictException,
    );
    expect((prisma as any).deviceToken.upsert).not.toHaveBeenCalled();
  });

  // notify() also persists to the inbox before enqueuing the push.
  const inboxPrisma = {
    notification: { create: jest.fn().mockResolvedValue({}) },
  } as never;

  it('notify enqueues a job rather than sending inline (durable)', async () => {
    const queue = makeQueue();
    const provider = makeProvider();
    const svc = new NotificationsService(inboxPrisma, provider, queue);

    await svc.notify('u1', { title: 'Hi', body: 'there' });

    expect(provider.send).not.toHaveBeenCalled();
    expect((queue as any).add).toHaveBeenCalledTimes(1);
    const [job, data] = (queue as any).add.mock.calls[0];
    expect(job).toBe(NOTIFY_JOB);
    expect(data).toEqual({ userId: 'u1', message: { title: 'Hi', body: 'there' } });
  });

  it('notifyTrip enqueues the canonical copy for a milestone with kind in data', async () => {
    const queue = makeQueue();
    const svc = new NotificationsService(inboxPrisma, makeProvider(), queue);

    await svc.notifyTrip('u1', 'arrived', { tripId: 't1' });

    const [, data] = (queue as any).add.mock.calls[0];
    expect(data.userId).toBe('u1');
    expect(data.message.title).toBe('Your driver has arrived');
    expect(data.message.data).toEqual({ kind: 'arrived', tripId: 't1' });
  });

  it('deliver pushes to every registered device of a user', async () => {
    const prisma = {
      deviceToken: {
        findMany: jest.fn().mockResolvedValue([
          { token: 'a', platform: 'android' },
          { token: 'b', platform: 'ios' },
        ]),
      },
    } as never;
    const provider = makeProvider();
    const svc = new NotificationsService(prisma, provider, makeQueue());

    await svc.deliver('u1', { title: 'Hi', body: 'there' });

    expect(provider.send).toHaveBeenCalledTimes(2);
  });

  it('deliver is a no-op when the user has no devices', async () => {
    const prisma = {
      deviceToken: { findMany: jest.fn().mockResolvedValue([]) },
    } as never;
    const provider = makeProvider();
    const svc = new NotificationsService(prisma, provider, makeQueue());

    await svc.deliver('u1', { title: 'Hi', body: 'there' });

    expect(provider.send).not.toHaveBeenCalled();
  });

  it('deliver prunes UNREGISTERED tokens and still delivers to the rest', async () => {
    const deleteMany = jest.fn().mockResolvedValue({ count: 1 });
    const prisma = {
      deviceToken: {
        findMany: jest.fn().mockResolvedValue([
          { token: 'stale', platform: 'android' },
          { token: 'good', platform: 'ios' },
        ]),
        deleteMany,
      },
    } as never;
    const provider = {
      send: jest.fn(({ token }: { token: string }) =>
        token === 'stale'
          ? Promise.reject(new StalePushTokenError('FCM send failed (404): UNREGISTERED'))
          : Promise.resolve(),
      ),
    } as unknown as PushProvider;
    const svc = new NotificationsService(prisma, provider, makeQueue());

    await expect(svc.deliver('u1', { title: 'Hi', body: 'there' })).resolves.toBeUndefined();

    expect(provider.send).toHaveBeenCalledTimes(2);
    expect(deleteMany).toHaveBeenCalledWith({ where: { token: { in: ['stale'] } } });
  });

  it('deliver does not fail the job when one device errors but another was reached', async () => {
    const prisma = {
      deviceToken: {
        findMany: jest.fn().mockResolvedValue([
          { token: 'flaky', platform: 'android' },
          { token: 'good', platform: 'ios' },
        ]),
        deleteMany: jest.fn(),
      },
    } as never;
    const provider = {
      send: jest.fn(({ token }: { token: string }) =>
        token === 'flaky' ? Promise.reject(new Error('503')) : Promise.resolve(),
      ),
    } as unknown as PushProvider;
    const svc = new NotificationsService(prisma, provider, makeQueue());

    await expect(svc.deliver('u1', { title: 'Hi', body: 'there' })).resolves.toBeUndefined();
    expect(provider.send).toHaveBeenCalledTimes(2);
    expect((prisma as any).deviceToken.deleteMany).not.toHaveBeenCalled();
  });

  it('deliver succeeds silently when every token was stale (nothing to retry)', async () => {
    const prisma = {
      deviceToken: {
        findMany: jest.fn().mockResolvedValue([{ token: 'stale', platform: 'android' }]),
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    } as never;
    const provider = {
      send: jest.fn().mockRejectedValue(new StalePushTokenError('gone')),
    } as PushProvider;
    const svc = new NotificationsService(prisma, provider, makeQueue());
    await expect(svc.deliver('u1', { title: 'Hi', body: 'there' })).resolves.toBeUndefined();
  });

  it('deliver rejects on a provider failure so the queue can retry', async () => {
    const prisma = {
      deviceToken: {
        findMany: jest.fn().mockResolvedValue([{ token: 'a', platform: 'android' }]),
      },
    } as never;
    const provider = {
      send: jest.fn().mockRejectedValue(new Error('boom')),
    } as PushProvider;
    const svc = new NotificationsService(prisma, provider, makeQueue());

    await expect(
      svc.deliver('u1', { title: 'Hi', body: 'there' }),
    ).rejects.toThrow('boom');
  });
});
