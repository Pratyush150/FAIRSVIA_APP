import { ActivityService } from './activity.service';

function build(opts: { redisSet?: string | null; insertFails?: boolean } = {}) {
  const set = jest.fn().mockResolvedValue(opts.redisSet === undefined ? 'OK' : opts.redisSet);
  const del = jest.fn().mockResolvedValue(1);
  const executeRaw = opts.insertFails
    ? jest.fn().mockRejectedValue(new Error('db down'))
    : jest.fn().mockResolvedValue(1);
  const svc = new ActivityService(
    { get: () => 'Asia/Tashkent' } as never,
    { $executeRaw: executeRaw } as never,
    { client: { set, del } } as never,
  );
  return { svc, set, del, executeRaw };
}

const flush = () => new Promise((r) => setImmediate(r));

describe('ActivityService', () => {
  it('writes a user once per Tashkent day, however many requests they make', async () => {
    const { svc, set, executeRaw } = build();
    const morning = new Date('2026-09-23T04:00:00Z'); // 09:00 Tashkent
    svc.touch('u1', morning);
    svc.touch('u1', morning);
    svc.touch('u1', new Date('2026-09-23T15:00:00Z')); // 20:00 Tashkent
    await flush();
    expect(set).toHaveBeenCalledTimes(1);
    expect(set.mock.calls[0][0]).toBe('active:2026-09-23:u1');
    expect(executeRaw).toHaveBeenCalledTimes(1);
  });

  it('starts a new day at Tashkent midnight, not UTC midnight', async () => {
    const { svc, set } = build();
    svc.touch('u1', new Date('2026-09-23T18:59:00Z')); // 23:59 Tashkent
    svc.touch('u1', new Date('2026-09-23T19:01:00Z')); // 00:01 next day
    await flush();
    expect(set.mock.calls.map((c) => c[0])).toEqual([
      'active:2026-09-23:u1',
      'active:2026-09-24:u1',
    ]);
  });

  it('skips the database when another instance already recorded today', async () => {
    const { svc, executeRaw } = build({ redisSet: null });
    svc.touch('u1');
    await flush();
    expect(executeRaw).not.toHaveBeenCalled();
  });

  it('retries on a later request when the write fails, and never throws', async () => {
    const { svc, set, del } = build({ insertFails: true });
    expect(() => svc.touch('u1')).not.toThrow();
    await flush();
    await flush();
    // The marker is removed so the next instance or request tries again.
    expect(del).toHaveBeenCalled();
    svc.touch('u1');
    await flush();
    expect(set).toHaveBeenCalledTimes(2);
  });
});
