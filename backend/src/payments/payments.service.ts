import {
  BadRequestException,
  ForbiddenException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../common/prisma/prisma.service';
import {
  PAYMENT_PROVIDER,
  PaymentProvider,
} from './payment-provider.interface';
import { AddMethodDto } from './dto/add-method.dto';
import { LedgerService } from '../ledger/ledger.service';

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
  ) {}

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

    const method = await this.defaultMethod(trip.riderId);
    const intent = await this.provider.authorize({
      amount,
      currency: trip.currency,
      customerRef: trip.riderId,
      methodRef: method?.externalId ?? undefined,
      description: `Ride ${tripId}`,
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
      },
      update: { status: intent.status, externalIntentId: intent.intentId },
    });
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
    const platformFee = round2(final * this.feePercent);
    const driverPayout = round2(final - platformFee);

    // Cash: the driver collects the fare in person, so there is no provider
    // charge. We still record the split — the platform fee is what the driver
    // owes on this ride (reconciled against their payout ledger).
    if (trip.paymentMode === 'cash') {
      await this.prisma.payment.upsert({
        where: { tripId },
        create: {
          tripId,
          amount: final,
          currency: trip.currency,
          status: 'collected',
          kind: 'ride',
          method: 'cash',
          platformFee,
          driverPayout,
        },
        update: {
          status: 'collected',
          method: 'cash',
          amount: final,
          platformFee,
          driverPayout,
        },
      });
      // Cash in the driver's hand — they owe the platform its commission.
      if (trip.driverId) {
        await this.ledger.record(trip.driverId, 'commission', -platformFee, {
          tripId,
          note: 'Commission owed on cash ride',
        });
      }
      return { fareFinal: final, platformFee, driverPayout };
    }

    const existing = await this.prisma.payment.findUnique({ where: { tripId } });
    // If a hold exists, capture it; otherwise charge directly.
    if (existing?.externalIntentId && existing.status === 'authorized') {
      await this.provider.capture(existing.externalIntentId, final);
    } else if (final > 0) {
      const method = await this.defaultMethod(trip.riderId);
      const intent = await this.provider.charge({
        amount: final,
        currency: trip.currency,
        customerRef: trip.riderId,
        methodRef: method?.externalId ?? undefined,
        description: `Ride ${tripId}`,
      });
      await this.prisma.payment.upsert({
        where: { tripId },
        create: {
          tripId,
          amount: final,
          currency: trip.currency,
          status: 'captured',
          kind: 'ride',
          externalIntentId: intent.intentId,
        },
        update: { externalIntentId: intent.intentId },
      });
    }

    await this.prisma.payment.update({
      where: { tripId },
      data: { status: 'captured', amount: final, platformFee, driverPayout },
    });
    // Card ride captured by the platform — credit the driver their net payout.
    if (trip.driverId) {
      await this.ledger.record(trip.driverId, 'earning', driverPayout, {
        tripId,
        note: 'Ride earning',
      });
    }
    return { fareFinal: final, platformFee, driverPayout };
  }

  /** A cancellation fee charged immediately (partly paid to the driver). */
  async chargeCancellationFee(tripId: string, amount: number): Promise<number> {
    if (amount <= 0) return 0;
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) return 0;

    const method = await this.defaultMethod(trip.riderId);
    const intent = await this.provider.charge({
      amount,
      currency: trip.currency,
      customerRef: trip.riderId,
      methodRef: method?.externalId ?? undefined,
      description: `Cancellation fee ${tripId}`,
    });
    const platformFee = round2(amount * this.feePercent);
    await this.prisma.payment.upsert({
      where: { tripId },
      create: {
        tripId,
        amount,
        currency: trip.currency,
        status: 'captured',
        kind: 'cancellation',
        externalIntentId: intent.intentId,
        platformFee,
        driverPayout: round2(amount - platformFee),
      },
      update: {
        status: 'captured',
        kind: 'cancellation',
        amount,
        platformFee,
        driverPayout: round2(amount - platformFee),
        externalIntentId: intent.intentId,
      },
    });
    // Compensate the driver for the wasted trip-to-pickup (their fee share).
    if (trip.driverId) {
      await this.ledger.record(
        trip.driverId,
        'earning',
        round2(amount - platformFee),
        { tripId, note: 'Cancellation compensation' },
      );
    }
    return amount;
  }

  /**
   * Refund a settled ride payment (full or partial), reversing the driver's
   * earning proportionally. Admin-initiated. Card payments hit the provider;
   * cash refunds are recorded only (settled with the rider out-of-band).
   */
  async refundTrip(tripId: string, amount?: number, reason?: string) {
    const payment = await this.prisma.payment.findUnique({ where: { tripId } });
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
        `Refund must be between 0 and ₹${remaining.toFixed(2)}`,
      );
    }

    if (payment.externalIntentId) {
      await this.provider.refund(payment.externalIntentId, refund);
    }

    const refundedAmount = round2(already + refund);
    // 'partial' (not 'partially_refunded') to fit the status VarChar(12).
    const status = refundedAmount >= total ? 'refunded' : 'partial';
    await this.prisma.payment.update({
      where: { tripId },
      data: { refundedAmount, status, refundReason: reason ?? null },
    });

    // Claw back the driver's share of the refunded amount (net of platform fee).
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (trip?.driverId) {
      const clawback = round2(refund * (1 - this.feePercent));
      await this.ledger.record(trip.driverId, 'adjustment', -clawback, {
        tripId,
        note: `Refund clawback${reason ? `: ${reason}` : ''}`,
      });
    }

    return { tripId, refunded: refund, totalRefunded: refundedAmount, status };
  }

  async addTip(userId: string, tripId: string, amount: number) {
    if (amount <= 0) throw new BadRequestException('Tip must be positive');
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) throw new NotFoundException('Trip not found');
    if (trip.riderId !== userId) {
      throw new ForbiddenException('Only the rider can tip');
    }

    const method = await this.defaultMethod(userId);
    await this.provider.charge({
      amount,
      currency: trip.currency,
      customerRef: userId,
      methodRef: method?.externalId ?? undefined,
      description: `Tip ${tripId}`,
    });

    const payment = await this.prisma.payment.findUnique({ where: { tripId } });
    const newTip = round2(Number(payment?.tip ?? 0) + amount);
    const newPayout = round2(Number(payment?.driverPayout ?? 0) + amount);
    const updated = await this.prisma.payment.update({
      where: { tripId },
      data: { tip: newTip, driverPayout: newPayout },
    });
    // A tip is paid in full to the driver.
    if (trip.driverId) {
      await this.ledger.record(trip.driverId, 'tip', amount, {
        tripId,
        note: 'Tip',
      });
    }
    return { tip: Number(updated.tip), driverPayout: Number(updated.driverPayout) };
  }

  async listMethods(userId: string) {
    return this.prisma.paymentMethod.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
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
    return {
      tripId,
      status: trip.status,
      distanceM: trip.distanceM,
      durationS: trip.durationS,
      currency: trip.currency,
      fare: Number(trip.fareFinal ?? trip.fareEstimate ?? 0),
      paymentMode: trip.paymentMode,
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

  private async defaultMethod(userId: string) {
    return this.prisma.paymentMethod.findFirst({
      where: { userId, isDefault: true },
    });
  }
}
