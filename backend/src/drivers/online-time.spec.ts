import { splitByBusinessDay } from './online-time';

describe('splitByBusinessDay', () => {
  const tz = 'Asia/Kolkata'; // UTC+5:30, no DST

  it('credits a same-day session to that day', () => {
    const from = new Date('2026-09-25T04:30:00Z'); // 10:00 IST
    const to = new Date('2026-09-25T06:00:00Z'); // 11:30 IST
    expect(splitByBusinessDay(from, to, tz)).toEqual({ '2026-09-25': 5400 });
  });

  it('splits a session across local midnight', () => {
    const from = new Date('2026-09-24T18:00:00Z'); // 23:30 IST on the 24th
    const to = new Date('2026-09-24T19:00:00Z'); // 00:30 IST on the 25th
    expect(splitByBusinessDay(from, to, tz)).toEqual({
      '2026-09-24': 1800,
      '2026-09-25': 1800,
    });
  });

  it('returns nothing for an empty or inverted range', () => {
    const t = new Date('2026-09-25T06:00:00Z');
    expect(splitByBusinessDay(t, t, tz)).toEqual({});
    expect(splitByBusinessDay(t, new Date(t.getTime() - 1000), tz)).toEqual({});
  });

  it('caps a stale session start to the last maxDays', () => {
    const to = new Date('2026-09-25T06:00:00Z');
    const from = new Date(to.getTime() - 40 * 86400_000);
    const out = splitByBusinessDay(from, to, tz, 2);
    const total = Object.values(out).reduce((a, b) => a + b, 0);
    expect(total).toBe(2 * 86400);
  });
});
