import { ConflictException, Injectable, Logger } from '@nestjs/common';
import { Prisma, TripStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { MetricsService } from '../common/metrics/metrics.service';

/**
 * Server-authoritative allowed transitions (spec §6.2). Every transition is an
 * idempotent, optimistic-concurrency update guarded by the current status.
 */
export const ALLOWED_TRANSITIONS: Record<TripStatus, TripStatus[]> = {
  scheduled: [TripStatus.requested, TripStatus.cancelled, TripStatus.expired],
  requested: [TripStatus.matching, TripStatus.cancelled, TripStatus.expired],
  matching: [TripStatus.accepted, TripStatus.no_drivers, TripStatus.cancelled],
  accepted: [TripStatus.arrived, TripStatus.cancelled],
  arrived: [TripStatus.in_progress, TripStatus.cancelled],
  in_progress: [TripStatus.completed],
  completed: [TripStatus.payment_failed],
  cancelled: [],
  no_drivers: [],
  payment_failed: [],
  expired: [],
};

@Injectable()
export class TripStateMachine {
  private readonly logger = new Logger(TripStateMachine.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly metrics: MetricsService,
  ) {}

  isAllowed(from: TripStatus, to: TripStatus): boolean {
    return ALLOWED_TRANSITIONS[from]?.includes(to) ?? false;
  }

  /**
   * Atomically move a trip from [from] to [to] and append an audit event.
   * Uses `updateMany ... where status = from` so two concurrent callers can't
   * both win. Throws ConflictException if the trip isn't in [from].
   */
  async transition(params: {
    tripId: string;
    from: TripStatus;
    to: TripStatus;
    actor: string;
    // Unchecked variant allows setting scalar FKs (e.g. driverId) directly.
    data?: Prisma.TripUncheckedUpdateManyInput;
    meta?: Prisma.InputJsonValue;
  }): Promise<void> {
    const { tripId, from, to, actor, data, meta } = params;
    if (!this.isAllowed(from, to)) {
      throw new ConflictException(`Illegal transition ${from} -> ${to}`);
    }

    await this.prisma.$transaction(async (tx) => {
      const result = await tx.trip.updateMany({
        where: { id: tripId, status: from },
        data: { status: to, ...data },
      });
      if (result.count === 0) {
        throw new ConflictException(
          'Trip is no longer in the expected state (concurrent update).',
        );
      }
      await tx.tripEvent.create({
        data: {
          tripId,
          fromStatus: from,
          toStatus: to,
          actor,
          meta: meta ?? Prisma.JsonNull,
        },
      });
    });

    // Every trip transition passes through here, which makes this the one
    // place the funnel can be counted without sprinkling counters across six
    // services. Never allowed to affect the transition itself.
    void this.record(tripId, to);
  }

  /**
   * Feed the observability counters. Best-effort by construction: a metrics
   * problem must never turn a completed ride into a failed one.
   */
  private async record(tripId: string, to: TripStatus): Promise<void> {
    try {
      this.metrics.tripStatus(to);
      if (to !== TripStatus.accepted) return;
      // The match SLO: requested → accepted. Only read the row on accepts, so
      // the common transitions stay a single write.
      const trip = await this.prisma.trip.findUnique({
        where: { id: tripId },
        select: { requestedAt: true },
      });
      if (!trip?.requestedAt) return;
      this.metrics.observeMatch(
        (Date.now() - trip.requestedAt.getTime()) / 1000,
      );
    } catch (e) {
      this.logger.warn(`trip metric for ${tripId} -> ${to}: ${String(e)}`);
    }
  }
}
