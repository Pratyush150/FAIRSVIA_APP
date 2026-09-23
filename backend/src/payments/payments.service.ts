import {
  BadGatewayException,
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
  Optional,
} from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { Prisma, Trip, TripStatus } from '@prisma/client';
import { Queue } from 'bullmq';
import { PrismaService } from '../common/prisma/prisma.service';
import {
  PAYMENT_PROVIDER,
  PaymentProvider,
  ProviderRejectedException,
} from './payment-provider.interface';
import { AddMethodDto } from './dto/add-method.dto';
import { LedgerService } from '../ledger/ledger.service';
import { OpsFlagsService } from '../ops/ops-flags.service';
import { RealtimeService } from '../realtime/realtime.service';
import {
  StripeEvent,
  verifyStripeSignature,
  WebhookVerificationError,
} from './stripe-webhook.util';
import {
  CAPTURE_JOB,
  CAPTURE_JOB_OPTS,
  CaptureJobData,
  QUEUE_PAYMENTS,
} from './payments.queue';
import { isSerializationFailure } from '../common/prisma/serialization';

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly ledger: LedgerService,
    @Inject(PAYMENT_PROVIDER) private readonly provider: PaymentProvider,
    @InjectQueue(QUEUE_PAYMENTS) private readonly queue: Queue<CaptureJobData>,
    // Required, not @Optional(): a kill switch that silently does nothing
    // when it is not wired is worse than no kill switch at all.
    private readonly flags: OpsFlagsService,
    // Optional so the pure-logic unit tests can build the service without a
    // socket layer; production always has the (global) RealtimeService.
    @Optional() private readonly realtime?: RealtimeService,
  ) {}

  /**
   * Durably schedule a retry of captureForTrip (see PaymentsProcessor). Called
   * when the capture at completion fails: the trip is already completed, so
   * the fare must still be collected later rather than silently forgotten.
   * `jobId` is keyed to the trip so re-enqueueing is a no-op while a retry is
   * pending.
   */
  async enqueueCapture(tripId: string): Promise<void> {
    await this.queue.add(
      CAPTURE_JOB,
      { tripId },
      { ...CAPTURE_JOB_OPTS, jobId: `capture-${tripId}` },
    );
  }

  private get feePercent(): number {
    return this.config.get<number>('platformFeePercent') ?? 0.2;
  }

  /** Auth-hold at trip start (manual capture) for the estimated fare. */
  async authorizeForTrip(tripId: string): Promise<void> {
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) return;
    const amount = Number(trip.fareEstimate ?? 0);
    if (amount <= 0) return;

    // Cash rides are settled in person on completion — there is nothing to
    // auth-hold. Record a pending cash payment so the trip has a payment row.
    if (trip.paymentMode === 'cash') {
      await this.prisma.payment.upsert({
        where: { tripId },
        create: {
          tripId,
          amount,
          currency: trip.currency,
          status: 'pending',
          kind: 'ride',
          method: 'cash',
        },
        update: { amount, method: 'cash' },
      });
      return;
    }

    const [customerRef, existing, method] = await Promise.all([
      this.ensureCustomer(trip.riderId),
      this.prisma.payment.findUnique({ where: { tripId } }),
      this.methodFor(trip),
    ]);
    // One stable idempotency key per trip auth-hold, reused on retry.
    const idempotencyKey = existing?.idempotencyKey ?? randomUUID();
    const intent = await this.provider.authorize({
      amount,
      currency: trip.currency,
      customerRef,
      methodRef: method?.externalId ?? undefined,
      description: `Ride ${tripId}`,
      idempotencyKey,
    });

    await this.prisma.payment.upsert({
      where: { tripId },
      create: {
        tripId,
        amount,
        currency: trip.currency,
        status: intent.status,
        kind: 'ride',
        externalIntentId: intent.intentId,
        idempotencyKey,
      },
      update: {
        status: intent.status,
        externalIntentId: intent.intentId,
        idempotencyKey,
      },
    });
  }

  /**
   * Platform-fee / driver-payout split. The driver is paid on the GROSS fare
   * (before any promo): a discount the platform offered the rider must not
   * come out of the driver's pocket, so the platform's cut absorbs it (and
   * can go negative on a heavily discounted ride).
   */
  private splitFor(trip: { promoDiscount?: unknown }, final: number) {
    const discount = Number(trip.promoDiscount ?? 0);
    const gross = final + (Number.isFinite(discount) ? discount : 0);
    const driverPayout = round2(gross * (1 - this.feePercent));
    const platformFee = round2(final - driverPayout);
    return { platformFee, driverPayout };
  }

  /** Capture the final fare on completion and compute the payout split. */
  async captureForTrip(tripId: string): Promise<{
    fareFinal: number;
    platformFee: number;
    driverPayout: number;
  }> {
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) throw new NotFoundException('Trip not found');
    const final = Number(trip.fareFinal ?? trip.fareEstimate ?? 0);

    const existing = await this.prisma.payment.findUnique({ where: { tripId } });
    // Idempotent: if this trip was already captured/collected, return the stored
    // split instead of charging again and double-crediting the driver's ledger.
    if (
      existing &&
      (existing.status === 'captured' || existing.status === 'collected')
    ) {
      return {
        fareFinal: Number(existing.amount ?? final),
        platformFee: Number(existing.platformFee ?? 0),
        driverPayout: Number(existing.driverPayout ?? 0),
      };
    }

    // Cash: the driver collects the fare in person, so there is no provider
    // charge. We still record the split — the platform fee is what the driver
    // owes on this ride (reconciled against their payout ledger).
    if (trip.paymentMode === 'cash') {
      const { platformFee, driverPayout } = this.splitFor(trip, final);
      await this.prisma.payment.upsert({
        where: { tripId },
        create: {
          tripId,
          amount: final,
          currency: trip.currency,
          status: 'pending',
          kind: 'ride',
          method: 'cash',
        },
        update: { method: 'cash' },
      });
      // Cash in the driver's hand — they owe the platform its commission.
      const won = await this.settleRide(
        tripId,
        { status: 'collected', amount: final, platformFee, driverPayout },
        trip.driverId && {
          driverId: trip.driverId,
          type: 'commission',
          amount: -platformFee,
          note: 'Commission owed on cash ride',
        },
      );
      return won
        ? { fareFinal: final, platformFee, driverPayout }
        : this.storedSplit(tripId, final);
    }

    // Card: capture the hold if present, else charge directly. Never capture
    // more than we authorized — Stripe rejects amount_to_capture > the hold,
    // which would strand the payment in `authorized` and skip the driver's
    // earning. So collect up to the hold. (Follow-up: authorize a buffered hold
    // so the final fare rarely exceeds it.)
    let collected = final;
    if (existing?.externalIntentId && existing.status === 'authorized') {
      const authorized = Number(existing.amount ?? final);
      collected = Math.min(final, authorized);
      await this.provider.capture(
        existing.externalIntentId,
        collected,
        existing.idempotencyKey ? `${existing.idempotencyKey}-cap` : undefined,
      );
    } else if (final > 0) {
      const [customerRef, method] = await Promise.all([
        this.ensureCustomer(trip.riderId),
        this.methodFor(trip),
      ]);
      const idempotencyKey = existing?.idempotencyKey ?? randomUUID();
      const intent = await this.provider.charge({
        amount: final,
        currency: trip.currency,
        customerRef,
        methodRef: method?.externalId ?? undefined,
        description: `Ride ${tripId}`,
        idempotencyKey,
      });
      // Recorded as `pending` until settleRide below: a crash between here and
      // there retries through this branch with the same idempotency key, so
      // the provider dedupes the charge and the driver is credited once.
      await this.prisma.payment.upsert({
        where: { tripId },
        create: {
          tripId,
          amount: final,
          currency: trip.currency,
          status: 'pending',
          kind: 'ride',
          externalIntentId: intent.intentId,
          idempotencyKey,
        },
        update: { externalIntentId: intent.intentId, idempotencyKey },
      });
    }

    // Split on what we actually collected, so the driver is never credited more
    // than was captured.
    const { platformFee, driverPayout } = this.splitFor(trip, collected);
    const won = await this.settleRide(
      tripId,
      { status: 'captured', amount: collected, platformFee, driverPayout },
      trip.driverId && {
        driverId: trip.driverId,
        type: 'earning',
        amount: driverPayout,
        note: 'Ride earning',
      },
    );
    return won
      ? { fareFinal: collected, platformFee, driverPayout }
      : this.storedSplit(tripId, collected);
  }

  /**
   * Moves a ride payment to its settled state and books the driver's side of
   * it in ONE transaction. The status guard means only the first of two
   * concurrent settles (completion + a retry job) applies; the other returns
   * false and books nothing, so the driver is never credited twice and never
   * left uncredited by a crash between the two writes.
   */
  private async settleRide(
    tripId: string,
    data: {
      status: 'captured' | 'collected';
      amount: number;
      platformFee: number;
      driverPayout: number;
    },
    entry:
      | { driverId: string; type: 'earning' | 'commission'; amount: number; note: string }
      | null
      | '',
  ): Promise<boolean> {
    return this.prisma.$transaction(async (tx) => {
      const res = await tx.payment.updateMany({
        where: {
          tripId,
          status: { notIn: ['captured', 'collected', 'refunded', 'partial'] },
        },
        data,
      });
      if (res.count === 0) return false;
      if (entry) {
        await this.ledger.record(
          entry.driverId,
          entry.type,
          entry.amount,
          { tripId, note: entry.note },
          tx,
        );
      }
      return true;
    });
  }

  private async storedSplit(tripId: string, fallback: number) {
    const p = await this.prisma.payment.findUnique({ where: { tripId } });
    return {
      fareFinal: Number(p?.amount ?? fallback),
      platformFee: Number(p?.platformFee ?? 0),
      driverPayout: Number(p?.driverPayout ?? 0),
    };
  }

  /**
   * A cancellation fee charged immediately (partly paid to the driver). A cash
   * ride has no card to charge: the fee is recorded as owed (`pending`, method
   * `cash`) for the driver/ops to collect, with no provider call and no driver
   * credit (nothing was collected yet).
   */
  async chargeCancellationFee(tripId: string, amount: number): Promise<number> {
    if (amount <= 0) return 0;
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) return 0;
    const platformFee = round2(amount * this.feePercent);

    if (trip.paymentMode === 'cash') {
      await this.prisma.payment.upsert({
        where: { tripId },
        create: {
          tripId,
          amount,
          currency: trip.currency,
          status: 'pending',
          kind: 'cancellation',
          method: 'cash',
          platformFee,
          driverPayout: round2(amount - platformFee),
        },
        update: {
          status: 'pending',
          kind: 'cancellation',
          method: 'cash',
          amount,
          platformFee,
          driverPayout: round2(amount - platformFee),
        },
      });
      return amount;
    }

    const [customerRef, method] = await Promise.all([
      this.ensureCustomer(trip.riderId),
      this.methodFor(trip),
    ]);
    const intent = await this.provider.charge({
      amount,
      currency: trip.currency,
      customerRef,
      methodRef: method?.externalId ?? undefined,
      description: `Cancellation fee ${tripId}`,
      // Stable per trip: a retried cancel can never charge the fee twice.
      idempotencyKey: `cancel-fee-${tripId}`,
    });
    // Payment row and the driver's compensation commit together; a second
    // concurrent call finds the fee already captured and books nothing, or
    // loses the serializable race — either way the winner booked it once.
    // (The provider charge above is deduped by its per-trip idempotency key.)
    await this.prisma.$transaction(
      async (tx) => {
        const prev = await tx.payment.findUnique({ where: { tripId } });
        if (prev?.kind === 'cancellation' && prev.status === 'captured') return;
        const fields = {
          status: 'captured',
          kind: 'cancellation',
          amount,
          platformFee,
          driverPayout: round2(amount - platformFee),
          externalIntentId: intent.intentId,
        };
        await tx.payment.upsert({
          where: { tripId },
          create: { tripId, currency: trip.currency, ...fields },
          update: fields,
        });
        // Compensate the driver for the wasted trip-to-pickup (their fee share).
        if (trip.driverId) {
          await this.ledger.record(
            trip.driverId,
            'earning',
            round2(amount - platformFee),
            { tripId, note: 'Cancellation compensation' },
            tx,
          );
        }
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    ).catch((e) => {
      if (!isSerializationFailure(e)) throw e;
    });
    return amount;
  }

  /**
   * Refund a settled ride payment (full or partial), reversing the driver's
   * earning proportionally. Admin-initiated. Card payments hit the provider;
   * cash refunds are recorded only (settled with the rider out-of-band).
   *
   * Two phases so the provider call can never be duplicated:
   *  1. RESERVE (serializable txn, committed): validate the remaining balance,
   *     bump `refundedAmount`, write the driver clawback and insert a `pending`
   *     PaymentRefund row. Two concurrent refunds can't both read the same
   *     balance — the loser gets a serialization failure (surfaced as a retry)
   *     with nothing sent to the provider.
   *  2. PROVIDER: call Stripe keyed on the refund row's id (Idempotency-Key),
   *     then mark the row `succeeded`. On failure the row is marked `failed`
   *     and the reservation (amount + clawback) is reversed in a second txn,
   *     so the books never show money returned that the rider didn't get.
   */
  async refundTrip(tripId: string, amount?: number, reason?: string) {
    let reserved: {
      refundId: string;
      refund: number;
      refundedAmount: number;
      status: string;
      externalIntentId: string | null;
      driverId: string | null;
      clawback: number;
      previousStatus: string;
    };
    try {
      reserved = await this.prisma.$transaction(
        async (tx) => {
          const payment = await tx.payment.findUnique({ where: { tripId } });
          if (!payment) throw new NotFoundException('No payment for this trip');
          if (!['captured', 'collected', 'partial'].includes(payment.status)) {
            throw new BadRequestException(
              `A ${payment.status} payment cannot be refunded`,
            );
          }
          const total = Number(payment.amount);
          const already = Number(payment.refundedAmount);
          const remaining = round2(total - already);
          const refund = amount != null ? round2(amount) : remaining;
          if (refund <= 0 || refund > remaining) {
            throw new BadRequestException(
              `Refund must be between 0 and $${remaining.toFixed(2)}`,
            );
          }

          const refundedAmount = round2(already + refund);
          // 'partial' (not 'partially_refunded') to fit the status VarChar(12).
          const status = refundedAmount >= total ? 'refunded' : 'partial';
          await tx.payment.update({
            where: { tripId },
            data: { refundedAmount, status, refundReason: reason ?? null },
          });
          const record = await tx.paymentRefund.create({
            data: {
              paymentId: payment.id,
              tripId,
              amount: refund,
              status: 'pending',
              reason: reason ?? null,
            },
          });

          // Claw back the driver's share (net of platform fee), in the same txn.
          const trip = await tx.trip.findUnique({ where: { id: tripId } });
          let clawback = 0;
          if (trip?.driverId) {
            clawback = round2(refund * (1 - this.feePercent));
            if (clawback !== 0) {
              await tx.ledgerEntry.create({
                data: {
                  driverId: trip.driverId,
                  type: 'adjustment',
                  amount: round2(-clawback),
                  tripId,
                  note: `Refund clawback${reason ? `: ${reason}` : ''}`,
                },
              });
            }
          }

          return {
            refundId: record.id,
            refund,
            refundedAmount,
            status,
            externalIntentId: payment.externalIntentId,
            driverId: trip?.driverId ?? null,
            clawback,
            previousStatus: payment.status,
          };
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (e) {
      if (
        isSerializationFailure(e)
      ) {
        throw new BadRequestException('Please try again.');
      }
      throw e;
    }

    // Phase 2: the provider call, keyed on the committed record so a duplicate
    // delivery (client retry, worker restart) is collapsed by Stripe.
    let externalRefundId: string | null = null;
    if (reserved.externalIntentId) {
      try {
        const res = await this.provider.refund(
          reserved.externalIntentId,
          reserved.refund,
          `refund-${reserved.refundId}`,
        );
        externalRefundId = typeof res === 'string' ? res : null;
      } catch (e) {
        await this.failRefund(tripId, reserved, e);
        throw new BadRequestException(
          'The payment provider could not process the refund. Nothing was refunded.',
        );
      }
    }
    await this.prisma.paymentRefund.update({
      where: { id: reserved.refundId },
      data: { status: 'succeeded', externalRefundId },
    });

    return {
      tripId,
      refundId: reserved.refundId,
      refunded: reserved.refund,
      totalRefunded: reserved.refundedAmount,
      status: reserved.status,
    };
  }

  /** Mark a reserved refund failed and reverse its reservation. */
  private async failRefund(
    tripId: string,
    reserved: {
      refundId: string;
      refund: number;
      driverId: string | null;
      clawback: number;
      previousStatus: string;
    },
    error: unknown,
  ): Promise<void> {
    this.logger.error(
      `refund ${reserved.refundId} for trip ${tripId} failed at provider: ${String(error)}`,
    );
    await this.prisma.$transaction(async (tx) => {
      await tx.paymentRefund.update({
        where: { id: reserved.refundId },
        data: {
          status: 'failed',
          failureMessage: String(
            (error as { message?: string })?.message ?? error,
          ).slice(0, 500),
        },
      });
      await tx.payment.update({
        where: { tripId },
        data: {
          refundedAmount: { decrement: reserved.refund },
          status: reserved.previousStatus,
        },
      });
      if (reserved.driverId && reserved.clawback !== 0) {
        await tx.ledgerEntry.create({
          data: {
            driverId: reserved.driverId,
            type: 'adjustment',
            amount: reserved.clawback,
            tripId,
            note: 'Refund clawback reversed (provider refund failed)',
          },
        });
      }
    });
  }

  /**
   * Tip the driver after a completed trip. One tip per trip: a second call is
   * rejected with 409 rather than re-charging the card and double-crediting
   * the driver (the previous per-trip idempotency key made the provider call a
   * no-op while the DB/ledger increments still ran). Cash rides record the tip
   * as handed over in cash — no card charge and no ledger credit, because the
   * driver already holds the money.
   */
  async addTip(userId: string, tripId: string, amount: number) {
    if (amount <= 0) throw new BadRequestException('Tip must be positive');
    const tip = round2(amount);
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) throw new NotFoundException('Trip not found');
    if (trip.riderId !== userId) {
      throw new ForbiddenException('Only the rider can tip');
    }
    if (trip.status !== TripStatus.completed) {
      throw new BadRequestException('You can only tip a completed trip');
    }
    const payment = await this.prisma.payment.findUnique({ where: { tripId } });
    if (!payment) {
      throw new BadRequestException('This trip has no settled payment to tip on');
    }
    if (Number(payment.tip) > 0) {
      throw new ConflictException('A tip was already added to this trip');
    }

    // How the tip is collected mirrors how the ride was paid:
    //  - Cash ride: the rider hands the tip to the driver in cash — record it,
    //    never charge a card (there may be none, and charging would fail).
    //  - Card ride: charge the card the ride used (falling back to the default).
    //    With no chargeable method, record the tip anyway rather than failing
    //    the whole action (the driver is still credited; reconciled out-of-band).
    if (trip.paymentMode !== 'cash') {
      const [customerRef, method] = await Promise.all([
        this.ensureCustomer(userId),
        this.methodFor(trip),
      ]);
      if (method?.externalId) {
        await this.provider.charge({
          amount: tip,
          currency: trip.currency,
          customerRef,
          methodRef: method.externalId,
          description: `Tip ${tripId}`,
          // Stable key per trip so a client retry can't double-charge the tip.
          idempotencyKey: `tip-${tripId}`,
        });
      }
    }

    // Guarded increment: only the first writer (tip still 0) applies. A race
    // that slipped past the read above lands here as count 0 → 409.
    // The tip and the driver's credit commit together.
    const applied = await this.prisma.$transaction(async (tx) => {
      const res = await tx.payment.updateMany({
        where: { tripId, tip: 0 },
        data: { tip: { increment: tip }, driverPayout: { increment: tip } },
      });
      if (res.count === 0) return false;
      // A card tip is collected by the platform and paid in full to the
      // driver. A cash tip is already in the driver's hand — nothing to credit.
      if (trip.driverId && trip.paymentMode !== 'cash') {
        await this.ledger.record(
          trip.driverId,
          'tip',
          tip,
          { tripId, note: 'Tip' },
          tx,
        );
      }
      return true;
    });
    if (!applied) {
      throw new ConflictException('A tip was already added to this trip');
    }
    const result = {
      tip: round2(Number(payment.tip) + tip),
      driverPayout: round2(Number(payment.driverPayout ?? 0) + tip),
      paymentMode: trip.paymentMode,
    };
    // The driver's completion sheet is still up: let it show the tip (cash:
    // more to collect; card: more earned) instead of the pre-tip numbers.
    if (trip.driverId) {
      this.realtime?.emitToUser(trip.driverId, 'trip:tip_added', {
        tripId,
        added: tip,
        ...result,
      });
    }
    return result;
  }

  async listMethods(userId: string) {
    return this.prisma.paymentMethod.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
  }

  /** Ownership-checked lookup shared by the mutating method routes. */
  private async ownedMethod(userId: string, id: string) {
    const method = await this.prisma.paymentMethod.findFirst({
      where: { id, userId },
    });
    if (!method) throw new NotFoundException('Payment method not found');
    return method;
  }

  async setDefaultMethod(userId: string, id: string) {
    await this.ownedMethod(userId, id);
    await this.prisma.$transaction(async (tx) => {
      await tx.paymentMethod.updateMany({
        where: { userId, isDefault: true },
        data: { isDefault: false },
      });
      await tx.paymentMethod.update({ where: { id }, data: { isDefault: true } });
    });
    return this.listMethods(userId);
  }

  async removeMethod(userId: string, id: string) {
    const method = await this.ownedMethod(userId, id);
    await this.prisma.$transaction(async (tx) => {
      await tx.paymentMethod.delete({ where: { id } });
      if (method.isDefault) {
        // Promote the newest remaining card so "pay by card" keeps working.
        const next = await tx.paymentMethod.findFirst({
          where: { userId },
          orderBy: { createdAt: 'desc' },
        });
        if (next) {
          await tx.paymentMethod.update({
            where: { id: next.id },
            data: { isDefault: true },
          });
        }
      }
    });
    return { deleted: true };
  }

  async addMethod(userId: string, dto: AddMethodDto) {
    const isFirst = (await this.prisma.paymentMethod.count({ where: { userId } })) === 0;
    return this.prisma.paymentMethod.create({
      data: {
        userId,
        provider: this.config.get<string>('stripeSecretKey') ? 'stripe' : 'mock',
        externalId: dto.externalId,
        brand: dto.brand,
        last4: dto.last4,
        isDefault: isFirst,
      },
    });
  }

  async getReceipt(userId: string, tripId: string) {
    const trip = await this.prisma.trip.findUnique({
      where: { id: tripId },
      include: { payment: true },
    });
    if (!trip) throw new NotFoundException('Trip not found');
    if (trip.riderId !== userId && trip.driverId !== userId) {
      throw new ForbiddenException('Not your trip');
    }
    const p = trip.payment;
    // The itemised fare is persisted on the completion event by
    // TripsService.settleFare (no trip column). Older trips have none → null.
    const completion = await this.prisma.tripEvent
      .findFirst({
        where: { tripId, toStatus: TripStatus.completed },
        orderBy: { createdAt: 'desc' },
        select: { meta: true },
      })
      .catch(() => null);
    const stored = (completion?.meta as { breakdown?: Record<string, number> } | null)
      ?.breakdown;
    const breakdown = stored
      ? {
          baseFare: Number(stored.baseFare ?? 0),
          distanceFare: Number(stored.distanceFare ?? 0),
          timeFare: Number(stored.timeFare ?? 0),
          bookingFee: Number(stored.bookingFee ?? 0),
          surgeMultiplier: Number(stored.surgeMultiplier ?? trip.surgeMultiplier ?? 1),
          promoDiscount: Number(stored.promoDiscount ?? trip.promoDiscount ?? 0),
          tip: Number(p?.tip ?? 0),
          minimumFareAdjustment: Number(stored.minimumFareAdjustment ?? 0),
        }
      : null;
    const card =
      trip.paymentMode !== 'cash' && trip.paymentMethodId
        ? await this.prisma.paymentMethod
            .findUnique({ where: { id: trip.paymentMethodId } })
            .then((m) => (m ? { brand: m.brand, last4: m.last4 } : null))
            .catch(() => null)
        : null;
    return {
      tripId,
      status: trip.status,
      distanceM: trip.distanceM,
      durationS: trip.durationS,
      currency: trip.currency,
      fare: Number(trip.fareFinal ?? trip.fareEstimate ?? 0),
      paymentMode: trip.paymentMode,
      // Which saved card paid (null for cash / no card on the trip).
      card,
      breakdown,
      payment: p
        ? {
            status: p.status,
            kind: p.kind,
            method: p.method,
            amount: Number(p.amount),
            tip: Number(p.tip),
            platformFee: p.platformFee ? Number(p.platformFee) : null,
            driverPayout: p.driverPayout ? Number(p.driverPayout) : null,
            refundedAmount: Number(p.refundedAmount),
            refundReason: p.refundReason,
          }
        : null,
    };
  }

  /**
   * Start (or resume) Connect Express onboarding for a driver: create the
   * connected account on first call, persist its id, and return a fresh hosted
   * onboarding link (links are single-use / short-lived, so we always mint one).
   */
  async connectOnboard(userId: string): Promise<{ url: string; accountId: string }> {
    const profile = await this.prisma.driverProfile.findUnique({
      where: { userId },
    });
    if (!profile) {
      throw new NotFoundException('Complete driver onboarding first');
    }
    let accountId = profile.stripeAccountId;
    if (!accountId) {
      const user = await this.prisma.user.findUnique({ where: { id: userId } });
      accountId = await this.provider.createConnectAccount({
        userId,
        email: user?.email ?? undefined,
      });
      await this.prisma.driverProfile.update({
        where: { userId },
        data: { stripeAccountId: accountId },
      });
    }
    const url = await this.provider.createAccountLink(
      accountId,
      this.config.get<string>('stripeConnectRefreshUrl') ?? '',
      this.config.get<string>('stripeConnectReturnUrl') ?? '',
    );
    return { url, accountId };
  }

  /**
   * Refresh a driver's payout readiness from the provider and persist the
   * `payoutsEnabled` flag (the account.updated webhook does the same; this is
   * the pull path the app polls after returning from onboarding).
   */
  async connectStatus(userId: string): Promise<{
    onboarded: boolean;
    payoutsEnabled: boolean;
    detailsSubmitted: boolean;
  }> {
    const profile = await this.prisma.driverProfile.findUnique({
      where: { userId },
    });
    if (!profile?.stripeAccountId) {
      return { onboarded: false, payoutsEnabled: false, detailsSubmitted: false };
    }
    const status = await this.provider.getAccount(profile.stripeAccountId);
    if (status.payoutsEnabled !== profile.payoutsEnabled) {
      await this.prisma.driverProfile.update({
        where: { userId },
        data: { payoutsEnabled: status.payoutsEnabled },
      });
    }
    return {
      onboarded: true,
      payoutsEnabled: status.payoutsEnabled,
      detailsSubmitted: status.detailsSubmitted,
    };
  }

  /**
   * Pay out available balance to the driver. When Connect payouts are enabled we
   * create a real transfer to their connected account, then record the ledger
   * movement; otherwise we fall back to the mock withdrawal (dev / not-yet-
   * onboarded). The balance guard lives in LedgerService for the mock path and
   * is mirrored here for the transfer path.
   */
  async payout(userId: string, amount: number) {
    // Kill switch: block withdrawals outright. A driver being told "payouts
    // are paused" is recoverable; money moving during a suspected ledger fault
    // is not.
    if (await this.flags.isOn('payoutsFrozen')) {
      throw new BadRequestException(
        'Payouts are temporarily paused. Your balance is safe and ' +
          'withdrawals will reopen shortly.',
      );
    }
    const profile = await this.prisma.driverProfile.findUnique({
      where: { userId },
    });
    if (profile?.stripeAccountId && profile.payoutsEnabled) {
      // Reserve first: the balance check and the debit are one serializable
      // transaction, so two concurrent payouts cannot both pass it. Only the
      // winner reaches the bank transfer, keyed on its own ledger entry so a
      // retry of THIS payout can't send the money twice. A failed transfer
      // gives the reservation back.
      const reserved = await this.ledger.withdraw(userId, amount, 'Payout to bank');
      let transferId: string;
      try {
        transferId = await this.provider.createTransfer({
          accountId: profile.stripeAccountId,
          amount: reserved.withdrawn,
          currency: 'USD',
          idempotencyKey: `payout-${reserved.entryId}`,
        });
      } catch (e) {
        if (e instanceof ProviderRejectedException) {
          // Definitely refused — no money moved, give the balance back.
          await this.ledger.reverseWithdrawal(userId, reserved.withdrawn, e.message);
          throw e;
        }
        // Timeout / 5xx: the transfer MAY have gone through. Keep the balance
        // reserved (reversing could pay the driver twice) and flag the entry
        // for reconciliation against Stripe with its idempotency key.
        this.logger.error(
          `payout ${reserved.entryId} outcome unknown for driver ${userId}: ${
            e instanceof Error ? e.message : e
          } — reconcile with Stripe (key payout-${reserved.entryId})`,
        );
        await this.prisma.ledgerEntry.update({
          where: { id: reserved.entryId },
          data: { note: 'Payout to bank — PENDING RECONCILIATION' },
        });
        throw new BadGatewayException(
          'Your payout is being processed. If it does not arrive, contact support — ' +
            'your balance is safe.',
        );
      }
      await this.prisma.ledgerEntry.update({
        where: { id: reserved.entryId },
        data: { note: `Payout to bank (${transferId})` },
      });
      return {
        withdrawn: reserved.withdrawn,
        balance: reserved.balance,
        transferId,
        mode: 'stripe' as const,
      };
    }
    // No Connect payouts yet — simulated withdrawal.
    const { entryId: _entryId, ...res } = await this.ledger.withdraw(userId, amount);
    return { ...res, transferId: null, mode: 'mock' as const };
  }

  /**
   * Verify + process an incoming Stripe webhook. Idempotent: the event id is
   * claimed in webhook_events before dispatch, so a redelivery is a no-op. Only
   * the events we act on are handled; the rest are acknowledged and ignored.
   */
  async handleWebhook(rawBody: Buffer, signature: string | undefined) {
    const secret = this.config.get<string>('stripeWebhookSecret') ?? '';
    if (!secret) {
      throw new BadRequestException('Stripe webhooks are not configured');
    }

    let event: StripeEvent;
    try {
      event = verifyStripeSignature(rawBody, signature, secret);
    } catch (e) {
      if (e instanceof WebhookVerificationError) {
        throw new BadRequestException(`Webhook signature failed: ${e.message}`);
      }
      throw e;
    }

    // Claim idempotency AND process the side effect in ONE transaction: if the
    // handler throws, the claim rolls back too, so Stripe's retry re-processes
    // instead of hitting the unique constraint and being acked as a no-op
    // (which would permanently lose the state change). A genuine duplicate — the
    // event was already processed and committed — still hits P2002 and is acked.
    try {
      await this.prisma.$transaction(async (tx) => {
        await tx.webhookEvent.create({
          data: { id: event.id, type: event.type },
        });
        switch (event.type) {
          case 'payment_intent.succeeded':
            await tx.payment.updateMany({
              where: { externalIntentId: event.data.object.id as string },
              data: { status: 'captured' },
            });
            break;
          case 'payment_intent.payment_failed':
            await tx.payment.updateMany({
              where: { externalIntentId: event.data.object.id as string },
              data: { status: 'failed' },
            });
            break;
          case 'account.updated':
            await tx.driverProfile.updateMany({
              where: { stripeAccountId: event.data.object.id as string },
              data: {
                payoutsEnabled: Boolean(event.data.object.payouts_enabled),
              },
            });
            break;
          default:
            this.logger.log(`Unhandled webhook event ${event.type}`);
        }
      });
    } catch (e) {
      if (
        e instanceof Prisma.PrismaClientKnownRequestError &&
        e.code === 'P2002'
      ) {
        return { received: true, duplicate: true };
      }
      throw e; // real processing error → 5xx → Stripe retries and re-processes
    }
    return { received: true };
  }

  /**
   * Return the rider's provider customer ref, creating (and persisting) one on
   * first use. Charges/holds reference this — never the raw FairsVia user id.
   */
  private async ensureCustomer(userId: string): Promise<string> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');
    if (user.stripeCustomerId) return user.stripeCustomerId;

    const customerRef = await this.provider.createCustomer({
      userId,
      email: user.email ?? undefined,
      name: user.fullName ?? undefined,
      phone: user.phone,
    });
    await this.prisma.user.update({
      where: { id: userId },
      data: { stripeCustomerId: customerRef },
    });
    return customerRef;
  }

  /**
   * Start a card-save: ensure the customer, mint a SetupIntent + ephemeral key,
   * and hand back the secrets the client PaymentSheet needs (plus the
   * publishable key so the SDK can initialise).
   */
  async createSetupIntent(userId: string) {
    const customerRef = await this.ensureCustomer(userId);
    const setup = await this.provider.createSetupIntent(customerRef);
    return {
      setupIntentClientSecret: setup.clientSecret,
      customerId: customerRef,
      ephemeralKeySecret: setup.ephemeralKeySecret ?? null,
      publishableKey: this.config.get<string>('stripePublishableKey') ?? '',
    };
  }

  /**
   * Pull the customer's saved cards from the provider and upsert them into our
   * local table (called after the client PaymentSheet saves a card). Keyed by
   * the provider payment-method ref so re-syncing is idempotent.
   */
  async syncMethods(userId: string) {
    const customerRef = await this.ensureCustomer(userId);
    const cards = await this.provider.listCards(customerRef);
    const provider = this.config.get<string>('stripeSecretKey') ? 'stripe' : 'mock';
    for (const card of cards) {
      const existing = await this.prisma.paymentMethod.findFirst({
        where: { userId, externalId: card.ref },
      });
      if (existing) {
        await this.prisma.paymentMethod.update({
          where: { id: existing.id },
          data: { brand: card.brand, last4: card.last4 },
        });
      } else {
        const isFirst =
          (await this.prisma.paymentMethod.count({ where: { userId } })) === 0;
        await this.prisma.paymentMethod.create({
          data: {
            userId,
            provider,
            externalId: card.ref,
            brand: card.brand,
            last4: card.last4,
            isDefault: isFirst,
          },
        });
      }
    }
    return this.listMethods(userId);
  }

  private async defaultMethod(userId: string) {
    return this.prisma.paymentMethod.findFirst({
      where: { userId, isDefault: true },
    });
  }

  /**
   * The saved card to charge for a trip: the method the rider picked at
   * booking (validated to belong to them at creation and persisted on the
   * trip), falling back to their default card only when none was chosen or it
   * has since been removed.
   */
  private async methodFor(
    trip: Pick<Trip, 'riderId' | 'paymentMethodId'>,
  ) {
    if (trip.paymentMethodId) {
      const chosen = await this.prisma.paymentMethod.findFirst({
        where: { id: trip.paymentMethodId, userId: trip.riderId },
      });
      if (chosen) return chosen;
    }
    return this.defaultMethod(trip.riderId);
  }
}
