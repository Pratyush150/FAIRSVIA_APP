import { Logger } from '@nestjs/common';
import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Job } from 'bullmq';
import { TripStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { NotificationsService } from '../notifications/notifications.service';
import { EmailService } from '../email/email.service';
import { TripStateMachine } from '../trips/trip-state-machine';
import { MetricsService } from '../common/metrics/metrics.service';
import { PaymentsService } from './payments.service';
import { CaptureJobData, QUEUE_PAYMENTS } from './payments.queue';

/**
 * Durable retry of a fare capture that failed at trip completion. The trip is
 * already `completed` (the ride happened); this job keeps trying to collect
 * the fare and, once it lands, emits the real fee/payout split to both parties
 * and sends the receipt. When every attempt is exhausted the trip is moved to
 * `payment_failed` so it is visible to admins instead of silently free.
 */
@Processor(QUEUE_PAYMENTS, { concurrency: 5 })
export class PaymentsProcessor extends WorkerHost {
  private readonly logger = new Logger('PaymentsProcessor');

  constructor(
    private readonly payments: PaymentsService,
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
    private readonly notifications: NotificationsService,
    private readonly email: EmailService,
    private readonly stateMachine: TripStateMachine,
    private readonly metrics: MetricsService,
  ) {
    super();
  }

  async process(job: Job<CaptureJobData>): Promise<void> {
    const { tripId } = job.data;
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) return;
    // Only a completed ride has a fare to collect; anything else (already
    // flagged payment_failed by an admin, refunded, ...) is a no-op.
    if (trip.status !== TripStatus.completed) return;

    try {
      const split = await this.payments.captureForTrip(tripId);
      const settled = {
        tripId,
        fareFinal: split.fareFinal,
        platformFee: split.platformFee,
        driverPayout: split.driverPayout,
        currency: trip.currency,
        paymentMode: trip.paymentMode,
        paymentStatus: 'captured' as const,
      };
      this.realtime.emitToUser(trip.riderId, 'trip:payment_settled', settled);
      if (trip.driverId) {
        this.realtime.emitToUser(trip.driverId, 'trip:payment_settled', settled);
      }
      const rider = await this.prisma.user.findUnique({
        where: { id: trip.riderId },
        select: { email: true },
      });
      await this.email.sendReceipt(rider?.email, tripId, split.fareFinal);
      this.logger.log(
        `captured trip ${tripId} on attempt ${job.attemptsMade + 1}: ${split.fareFinal}`,
      );
    } catch (e) {
      const attempts = job.opts.attempts ?? 1;
      const exhausted = job.attemptsMade + 1 >= attempts;
      this.logger.warn(
        `capture failed for trip ${tripId} (attempt ${job.attemptsMade + 1}/${attempts}): ${String(e)}`,
      );
      // Count every failed attempt, and mark the exhausted ones separately:
      // a burst of retries that eventually succeeds is a vendor blip, while a
      // rising `exhausted` line is money that never arrived.
      this.metrics.paymentFailed(
        'capture',
        exhausted ? 'exhausted' : 'retrying',
      );
      if (exhausted) await this.markPaymentFailed(tripId, trip.riderId, trip.driverId);
      throw e; // let BullMQ schedule the retry / record the final failure
    }
  }

  private async markPaymentFailed(
    tripId: string,
    riderId: string,
    driverId: string | null,
  ): Promise<void> {
    try {
      await this.stateMachine.transition({
        tripId,
        from: TripStatus.completed,
        to: TripStatus.payment_failed,
        actor: 'system',
        meta: { event: 'capture_retries_exhausted' },
      });
    } catch (e) {
      this.logger.error(`could not flag trip ${tripId} payment_failed: ${String(e)}`);
      return;
    }
    this.realtime.emitToUser(riderId, 'trip:payment_failed', { tripId });
    if (driverId) this.realtime.emitToUser(driverId, 'trip:payment_failed', { tripId });
    void this.notifications.notify(riderId, {
      title: 'Payment failed',
      body: 'We could not charge your card for your last ride. Please update your payment method.',
      data: { kind: 'payment_failed', tripId },
    });
  }

  onModuleDestroy(): Promise<void> {
    return this.worker?.close() ?? Promise.resolve();
  }
}
