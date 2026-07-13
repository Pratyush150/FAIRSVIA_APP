import { NotificationsService } from './notifications.service';
import { PushProvider } from './push-provider.interface';
import { NOTIFY_JOB } from '../common/queue/queue.constants';

describe('NotificationsService', () => {
  function makeProvider() {
    return { send: jest.fn().mockResolvedValue(undefined) } as PushProvider;
  }
  function makeQueue() {
    return { add: jest.fn().mockResolvedValue({}) } as never;
  }

  it('registers a device via upsert', async () => {
    const prisma = {
      deviceToken: { upsert: jest.fn().mockResolvedValue({}) },
    } as never;
    const svc = new NotificationsService(prisma, makeProvider(), makeQueue());

    await svc.register('u1', 'tok-1', 'ios');

    expect((prisma as any).deviceToken.upsert).toHaveBeenCalledWith({
      where: { token: 'tok-1' },
      create: { userId: 'u1', token: 'tok-1', platform: 'ios' },
      update: { userId: 'u1', platform: 'ios' },
    });
  });

  it('notify enqueues a job rather than sending inline (durable)', async () => {
    const queue = makeQueue();
    const provider = makeProvider();
    const svc = new NotificationsService({} as never, provider, queue);

    await svc.notify('u1', { title: 'Hi', body: 'there' });

    expect(provider.send).not.toHaveBeenCalled();
    expect((queue as any).add).toHaveBeenCalledTimes(1);
    const [job, data] = (queue as any).add.mock.calls[0];
    expect(job).toBe(NOTIFY_JOB);
    expect(data).toEqual({ userId: 'u1', message: { title: 'Hi', body: 'there' } });
  });

  it('notifyTrip enqueues the canonical copy for a milestone with kind in data', async () => {
    const queue = makeQueue();
    const svc = new NotificationsService({} as never, makeProvider(), queue);

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
