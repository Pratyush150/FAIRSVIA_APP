import { ConflictException } from '@nestjs/common';
import { TripStatus } from '@prisma/client';
import { TripStateMachine } from './trip-state-machine';

describe('TripStateMachine', () => {
  // isAllowed is a pure function; transition's guard runs before any DB call,
  // so a dummy prisma is fine for the illegal-transition test.
  const sm = new TripStateMachine({} as never);

  it('allows the canonical happy-path transitions', () => {
    expect(sm.isAllowed(TripStatus.requested, TripStatus.matching)).toBe(true);
    expect(sm.isAllowed(TripStatus.matching, TripStatus.accepted)).toBe(true);
    expect(sm.isAllowed(TripStatus.accepted, TripStatus.arrived)).toBe(true);
    expect(sm.isAllowed(TripStatus.arrived, TripStatus.in_progress)).toBe(true);
    expect(sm.isAllowed(TripStatus.in_progress, TripStatus.completed)).toBe(true);
  });

  it('allows cancellation from active pre-trip states', () => {
    expect(sm.isAllowed(TripStatus.requested, TripStatus.cancelled)).toBe(true);
    expect(sm.isAllowed(TripStatus.accepted, TripStatus.cancelled)).toBe(true);
    expect(sm.isAllowed(TripStatus.arrived, TripStatus.cancelled)).toBe(true);
  });

  it('rejects illegal transitions', () => {
    expect(sm.isAllowed(TripStatus.requested, TripStatus.completed)).toBe(false);
    expect(sm.isAllowed(TripStatus.completed, TripStatus.requested)).toBe(false);
    expect(sm.isAllowed(TripStatus.in_progress, TripStatus.cancelled)).toBe(false);
    expect(sm.isAllowed(TripStatus.cancelled, TripStatus.requested)).toBe(false);
  });

  it('transition() throws before touching the DB on an illegal move', async () => {
    await expect(
      sm.transition({
        tripId: 't1',
        from: TripStatus.completed,
        to: TripStatus.requested,
        actor: 'system',
      }),
    ).rejects.toBeInstanceOf(ConflictException);
  });
});
