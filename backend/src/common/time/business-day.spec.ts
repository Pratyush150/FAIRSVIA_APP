import { businessDayKey, startOfBusinessDay } from './business-day';

describe('business day', () => {
  it('starts the Tashkent day at 19:00 UTC the evening before', () => {
    // 2026-09-23 02:00 in Tashkent is still 22 Sep in UTC.
    const at = new Date('2026-09-22T21:00:00Z');
    expect(businessDayKey(at, 'Asia/Tashkent')).toBe('2026-09-23');
    expect(startOfBusinessDay(at, 'Asia/Tashkent').toISOString()).toBe(
      '2026-09-22T19:00:00.000Z',
    );
  });

  it('is plain UTC midnight for UTC', () => {
    const at = new Date('2026-09-23T10:30:00Z');
    expect(startOfBusinessDay(at, 'UTC').toISOString()).toBe('2026-09-23T00:00:00.000Z');
  });

  it('follows a daylight-saving zone on the day the clocks change', () => {
    // New York springs forward on 2026-03-08; midnight is still EST (UTC-5).
    const at = new Date('2026-03-08T20:00:00Z');
    expect(startOfBusinessDay(at, 'America/New_York').toISOString()).toBe(
      '2026-03-08T05:00:00.000Z',
    );
    // The next day's midnight is EDT (UTC-4).
    const next = new Date('2026-03-09T12:00:00Z');
    expect(startOfBusinessDay(next, 'America/New_York').toISOString()).toBe(
      '2026-03-09T04:00:00.000Z',
    );
  });
});
