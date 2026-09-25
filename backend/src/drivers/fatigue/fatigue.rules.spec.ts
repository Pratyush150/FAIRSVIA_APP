import { fatigueState } from './fatigue.rules';

describe('fatigueState (Uber rule: 12 h online, reset only by a 6 h break)', () => {
  const H = 3600;
  const cfg = { max: 12 * H, rest: 6 * H, warn: 30 * 60 };
  const now = Date.UTC(2026, 8, 25, 12);

  it('adds the open session to the closed-session total', () => {
    const s = fatigueState({ acc: 5 * H, lastOff: now - H * 1000, onlineSince: now - 2 * H * 1000 }, now, cfg);
    expect(s.onlineSeconds).toBe(7 * H);
    expect(s.remainingSeconds).toBe(5 * H);
    expect(s.overLimit).toBe(false);
    expect(s.warnAtSeconds).toBe(12 * H - 1800);
  });

  it('a short break does not reset the count', () => {
    const s = fatigueState({ acc: 11 * H, lastOff: now - 2 * H * 1000, onlineSince: null }, now, cfg);
    expect(s.onlineSeconds).toBe(11 * H);
  });

  it('a full 6 h break resets the count', () => {
    const s = fatigueState({ acc: 12 * H, lastOff: now - 6 * H * 1000, onlineSince: null }, now, cfg);
    expect(s.onlineSeconds).toBe(0);
    expect(s.overLimit).toBe(false);
    expect(s.resting).toBe(false);
  });

  it('over the limit while offline: resting with the time left in the break', () => {
    const s = fatigueState({ acc: 12 * H + 60, lastOff: now - 2 * H * 1000, onlineSince: null }, now, cfg);
    expect(s.overLimit).toBe(true);
    expect(s.resting).toBe(true);
    expect(s.restSecondsLeft).toBe(4 * H);
    expect(s.restUntil).toBe(new Date(now + 4 * H * 1000).toISOString());
  });

  it('over the limit while still online (mid-trip): the full break is still owed', () => {
    const s = fatigueState({ acc: 11 * H, lastOff: null, onlineSince: now - 2 * H * 1000 }, now, cfg);
    expect(s.overLimit).toBe(true);
    expect(s.resting).toBe(false);
    expect(s.restSecondsLeft).toBe(6 * H);
  });
});
