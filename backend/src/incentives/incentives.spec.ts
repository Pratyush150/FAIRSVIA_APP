import { computeRates, tally } from './driver-rates';
import { inWindow, questProgress } from './quest-math';
import { splitPayout } from '../common/money';

describe('driver rates', () => {
  it('acceptance = accepted / (accepted + declined + expired)', () => {
    const r = computeRates({ accepted: 7, declined: 2, expired: 1, cancelled: 0 });
    expect(r.offers).toBe(10);
    expect(r.acceptanceRate).toBe(0.7);
    expect(r.cancellationRate).toBe(0);
  });

  it('cancellation = driver cancels / accepted, no-shows excluded', () => {
    const c = tally([
      'accepted', 'accepted', 'accepted', 'accepted',
      'cancelled', 'cancelled_no_show', 'cancelled_no_show',
    ]);
    expect(c).toEqual({ accepted: 4, declined: 0, expired: 0, cancelled: 1 });
    expect(computeRates(c).cancellationRate).toBe(0.25);
  });

  it('null (not 0) when there is nothing to divide by', () => {
    const r = computeRates({ accepted: 0, declined: 0, expired: 0, cancelled: 0 });
    expect(r.acceptanceRate).toBeNull();
    expect(r.cancellationRate).toBeNull();
    // Declined everything: 0% acceptance, but no accepted trips to cancel.
    const d = computeRates({ accepted: 0, declined: 3, expired: 0, cancelled: 0 });
    expect(d.acceptanceRate).toBe(0);
    expect(d.cancellationRate).toBeNull();
  });

  it('cancellation rate never exceeds 100%', () => {
    expect(computeRates({ accepted: 1, declined: 0, expired: 0, cancelled: 3 }).cancellationRate).toBe(1);
  });
});

describe('quest math', () => {
  const q = {
    startsAt: new Date('2026-09-25T07:00:00Z'),
    endsAt: new Date('2026-09-25T11:00:00Z'),
    targetTrips: 10,
  };

  it('window is half-open [startsAt, endsAt)', () => {
    expect(inWindow(q, new Date('2026-09-25T06:59:59.999Z'))).toBe(false);
    expect(inWindow(q, new Date('2026-09-25T07:00:00Z'))).toBe(true);
    expect(inWindow(q, new Date('2026-09-25T10:59:59.999Z'))).toBe(true);
    expect(inWindow(q, new Date('2026-09-25T11:00:00Z'))).toBe(false);
  });

  it('progress caps at the target and completes on reaching it', () => {
    expect(questProgress(q, 6)).toEqual({ progress: 6, target: 10, completed: false });
    expect(questProgress(q, 10)).toEqual({ progress: 10, target: 10, completed: true });
    expect(questProgress(q, 13)).toEqual({ progress: 10, target: 10, completed: true });
  });
});

describe('splitPayout (whole-unit driver share)', () => {
  it('INR: driver gets whole rupees, platform the remainder, sum = fare', () => {
    for (const fare of [89, 178, 101, 245, 1, 999]) {
      const s = splitPayout(fare, fare, 0.8, 'INR');
      expect(Number.isInteger(s.driverPayout)).toBe(true);
      expect(Math.round((s.driverPayout + s.platformFee) * 100) / 100).toBe(fare);
    }
    expect(splitPayout(89, 89, 0.8, 'INR')).toEqual({ driverPayout: 71, platformFee: 18 });
  });

  it('INR with a promo: driver paid on gross, platform absorbs the discount', () => {
    const s = splitPayout(178, 128, 0.8, 'INR');
    expect(s.driverPayout).toBe(142);
    expect(s.platformFee).toBe(-14);
    expect(s.driverPayout + s.platformFee).toBe(128);
  });

  it('USD keeps cents', () => {
    expect(splitPayout(12.35, 12.35, 0.8, 'USD')).toEqual({ driverPayout: 9.88, platformFee: 2.47 });
  });
});
