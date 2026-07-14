import { TripStatus } from '@prisma/client';
import { ScheduledService } from './scheduled.service';
import { PrismaService } from '../common/prisma/prisma.service';
import { TripStateMachine } from '../trips/trip-state-machine';
import { DispatchService } from '../dispatch/dispatch.service';
import { NotificationsService } from '../notifications/notifications.service';
import { RealtimeService } from '../realtime/realtime.service';
import { Queue } from 'bullmq';

function build(tripStatus: TripStatus | null) {
  const trip =
    tripStatus === null
      ? null
      : { id: 't1', riderId: 'r1', status: tripStatus };
  const prisma = {
    trip: { findUnique: jest.fn().mockResolvedValue(trip) },
  } as unknown as PrismaService;
  const stateMachine = {
    transition: jest.fn().mockResolvedValue(undefined),
  } as unknown as TripStateMachine;
  const dispatch = {
    dispatchTrip: jest.fn().mockResolvedValue(undefined),
  } as unknown as DispatchService;
  const notifications = {
    notifyTrip: jest.fn().mockResolvedValue(undefined),
  } as unknown as NotificationsService;
  const realtime = { emitToUser: jest.fn() } as unknown as RealtimeService;
  const queue = { add: jest.fn().mockResolvedValue(undefined) } as unknown as Queue;
  const svc = new ScheduledService(
    prisma,
    stateMachine,
    dispatch,
    notifications,
    realtime,
    queue,
  );
  return { svc, stateMachine, dispatch, queue };
}

describe('ScheduledService', () => {
  it('promotes a due scheduled trip to requested and dispatches it', async () => {
    const { svc, stateMachine, dispatch } = build(TripStatus.scheduled);
    await svc.promote('t1');
    expect(stateMachine.transition).toHaveBeenCalledWith(
      expect.objectContaining({
        from: TripStatus.scheduled,
        to: TripStatus.requested,
      }),
    );
    expect(dispatch.dispatchTrip).toHaveBeenCalledWith('t1');
  });

  it('is a no-op when the trip was cancelled before its time', async () => {
    const { svc, stateMachine, dispatch } = build(TripStatus.cancelled);
    await svc.promote('t1');
    expect(stateMachine.transition).not.toHaveBeenCalled();
    expect(dispatch.dispatchTrip).not.toHaveBeenCalled();
  });

  it('is a no-op for a missing trip', async () => {
    const { svc, dispatch } = build(null);
    await svc.promote('gone');
    expect(dispatch.dispatchTrip).not.toHaveBeenCalled();
  });

  it('enqueues a delayed promotion job keyed to the trip', async () => {
    const { svc, queue } = build(TripStatus.scheduled);
    await svc.enqueue('t1', new Date(Date.now() + 3600_000));
    expect(queue.add).toHaveBeenCalledWith(
      expect.any(String),
      { tripId: 't1' },
      expect.objectContaining({ jobId: 'sched-t1' }),
    );
  });
});
