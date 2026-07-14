import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, Logger } from '@nestjs/common';
import { TripStatus } from '@prisma/client';
import { Queue } from 'bullmq';
import { PrismaService } from '../common/prisma/prisma.service';
import {
  DEFAULT_JOB_OPTS,
  PROMOTE_JOB,
  QUEUE_SCHEDULED,
} from '../common/queue/queue.constants';
import { DispatchService } from '../dispatch/dispatch.service';
import { NotificationsService } from '../notifications/notifications.service';
import { RealtimeService } from '../realtime/realtime.service';
import { TripStateMachine } from '../trips/trip-state-machine';

/** Earliest a ride may be scheduled: a small buffer avoids "schedule for now". */
export const MIN_LEAD_MS = 5 * 60 * 1000; // 5 minutes
/** Latest a ride may be scheduled ahead. */
export const MAX_LEAD_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

@Injectable()
export class ScheduledService {
  private readonly logger = new Logger('ScheduledService');

  constructor(
    private readonly prisma: PrismaService,
    private readonly stateMachine: TripStateMachine,
    private readonly dispatch: DispatchService,
    private readonly notifications: NotificationsService,
    private readonly realtime: RealtimeService,
    @InjectQueue(QUEUE_SCHEDULED) private readonly queue: Queue,
  ) {}

  /**
   * Enqueue a delayed job to promote a scheduled trip to a live request at its
   * scheduled time. `jobId` is keyed to the trip so re-scheduling replaces it,
   * and a cancelled trip's job becomes a harmless no-op (status guard below).
   */
  async enqueue(tripId: string, runAt: Date): Promise<void> {
    const delay = Math.max(0, runAt.getTime() - Date.now());
    await this.queue.add(
      PROMOTE_JOB,
      { tripId },
      { ...DEFAULT_JOB_OPTS, jobId: `sched-${tripId}`, delay },
    );
    this.logger.log(`scheduled trip ${tripId} in ${Math.round(delay / 1000)}s`);
  }

  /**
   * Promote a due scheduled trip: SCHEDULED→REQUESTED, then dispatch. Idempotent
   * — a trip that was cancelled (or already promoted) before the job fired is a
   * no-op. Safe to retry.
   */
  async promote(tripId: string): Promise<void> {
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip || trip.status !== TripStatus.scheduled) return;

    await this.stateMachine.transition({
      tripId,
      from: TripStatus.scheduled,
      to: TripStatus.requested,
      actor: 'system',
      data: { requestedAt: new Date() },
      meta: { event: 'scheduled_promoted' },
    });

    this.realtime.emitToUser(trip.riderId, 'trip:scheduled_started', { tripId });
    void this.notifications.notifyTrip(trip.riderId, 'scheduled_started', {
      tripId,
    });

    // Kick off matching (non-blocking, same as an on-demand request).
    void this.dispatch.dispatchTrip(tripId).catch(() => undefined);
  }
}
