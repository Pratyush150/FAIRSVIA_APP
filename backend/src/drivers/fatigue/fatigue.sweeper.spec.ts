import { FatigueSweeper } from './fatigue.sweeper';

describe('FatigueSweeper', () => {
  const H = 3600_000;
  const now = Date.UTC(2026, 8, 25, 12);

  function make(raw: Record<string, unknown>, onTrip = false) {
    const fatigue = {
      tracked: jest.fn().mockResolvedValue(['d1']),
      raw: jest.fn().mockResolvedValue({ warned: false, remindSince: 0, remindN: 0, lastOff: null, ...raw }),
      state: jest.fn().mockResolvedValue({ resting: true }),
      markWarned: jest.fn(),
      markReminded: jest.fn(),
    };
    const drivers = { forceOffline: jest.fn().mockResolvedValue(!onTrip) };
    const realtime = { emitToUser: jest.fn() };
    const notifications = { notify: jest.fn().mockResolvedValue(undefined) };
    const redis = { client: { srem: jest.fn(), set: jest.fn().mockResolvedValue('OK') } };
    const sweeper = new FatigueSweeper(
      redis as never,
      fatigue as never,
      drivers as never,
      realtime as never,
      notifications as never,
    );
    return { sweeper, fatigue, drivers, realtime, notifications };
  }
  const events = (rt: { emitToUser: jest.Mock }) => rt.emitToUser.mock.calls.map((c) => c[1]);

  it('forces an over-limit driver offline and tells them', async () => {
    const m = make({ acc: 11 * 3600, onlineSince: now - 1.5 * H });
    expect(await m.sweeper.tick(now, false)).toEqual({ d1: 'forced_offline' });
    expect(m.drivers.forceOffline).toHaveBeenCalledWith('d1', null, 'fatigue');
    expect(events(m.realtime)).toContain('driver:fatigue_locked');
    expect(m.notifications.notify).toHaveBeenCalled();
  });

  it('waits for the trip to end (forceOffline refuses mid-trip)', async () => {
    const m = make({ acc: 11 * 3600, onlineSince: now - 1.5 * H }, true);
    expect(await m.sweeper.tick(now, false)).toEqual({ d1: 'over_limit_on_trip' });
    expect(events(m.realtime)).not.toContain('driver:fatigue_locked');
  });

  it('warns once inside the last 30 min', async () => {
    const m = make({ acc: 11 * 3600, onlineSince: now - 0.6 * H });
    expect(await m.sweeper.tick(now, false)).toEqual({ d1: 'warned' });
    expect(events(m.realtime)).toEqual(['driver:fatigue_warning']);
    expect(m.fatigue.markWarned).toHaveBeenCalledWith('d1');
    const again = make({ acc: 11 * 3600, onlineSince: now - 0.6 * H, warned: true });
    expect(await again.sweeper.tick(now, false)).toEqual({ d1: 'ok' });
  });

  it('sends a soft break reminder every 4 h of one session, once each', async () => {
    const since = now - 4.2 * H;
    const m = make({ acc: 0, onlineSince: since });
    expect(await m.sweeper.tick(now, false)).toEqual({ d1: 'reminded' });
    expect(events(m.realtime)).toEqual(['driver:break_reminder']);
    expect(m.fatigue.markReminded).toHaveBeenCalledWith('d1', since, 1);
    const again = make({ acc: 0, onlineSince: since, remindSince: since, remindN: 1 });
    expect(await again.sweeper.tick(now, false)).toEqual({ d1: 'ok' });
  });

  it('drops drivers who are no longer online from the tracked set', async () => {
    const m = make({ acc: 0, onlineSince: null });
    expect(await m.sweeper.tick(now, false)).toEqual({ d1: 'untracked' });
  });
});
