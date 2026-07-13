import { NotificationsService } from './notifications.service';
import { PushProvider } from './push-provider.interface';

describe('NotificationsService', () => {
  function makeProvider() {
    return { send: jest.fn().mockResolvedValue(undefined) } as PushProvider;
  }

  it('registers a device via upsert', async () => {
    const prisma = {
      deviceToken: { upsert: jest.fn().mockResolvedValue({}) },
    } as never;
    const svc = new NotificationsService(prisma, makeProvider());

    await svc.register('u1', 'tok-1', 'ios');

    expect((prisma as any).deviceToken.upsert).toHaveBeenCalledWith({
      where: { token: 'tok-1' },
      create: { userId: 'u1', token: 'tok-1', platform: 'ios' },
      update: { userId: 'u1', platform: 'ios' },
    });
  });

  it('pushes to every registered device of a user', async () => {
    const prisma = {
      deviceToken: {
        findMany: jest.fn().mockResolvedValue([
          { token: 'a', platform: 'android' },
          { token: 'b', platform: 'ios' },
        ]),
      },
    } as never;
    const provider = makeProvider();
    const svc = new NotificationsService(prisma, provider);

    await svc.notify('u1', { title: 'Hi', body: 'there' });

    expect(provider.send).toHaveBeenCalledTimes(2);
  });

  it('is a no-op when the user has no devices', async () => {
    const prisma = {
      deviceToken: { findMany: jest.fn().mockResolvedValue([]) },
    } as never;
    const provider = makeProvider();
    const svc = new NotificationsService(prisma, provider);

    await svc.notify('u1', { title: 'Hi', body: 'there' });

    expect(provider.send).not.toHaveBeenCalled();
  });

  it('sends the canonical copy for a trip milestone with kind in data', async () => {
    const prisma = {
      deviceToken: {
        findMany: jest.fn().mockResolvedValue([{ token: 'a', platform: 'android' }]),
      },
    } as never;
    const provider = makeProvider();
    const svc = new NotificationsService(prisma, provider);

    await svc.notifyTrip('u1', 'arrived', { tripId: 't1' });

    const [, message] = (provider.send as jest.Mock).mock.calls[0];
    expect(message.title).toBe('Your driver has arrived');
    expect(message.data).toEqual({ kind: 'arrived', tripId: 't1' });
  });

  it('swallows a provider failure so one bad device does not break the rest', async () => {
    const prisma = {
      deviceToken: {
        findMany: jest.fn().mockResolvedValue([
          { token: 'a', platform: 'android' },
          { token: 'b', platform: 'ios' },
        ]),
      },
    } as never;
    const provider = {
      send: jest
        .fn()
        .mockRejectedValueOnce(new Error('boom'))
        .mockResolvedValueOnce(undefined),
    } as PushProvider;
    const svc = new NotificationsService(prisma, provider);

    await expect(
      svc.notify('u1', { title: 'Hi', body: 'there' }),
    ).resolves.toBeUndefined();
    expect(provider.send).toHaveBeenCalledTimes(2);
  });
});
