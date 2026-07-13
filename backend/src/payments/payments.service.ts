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

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
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
    return amount;
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
      payment: p
        ? {
            status: p.status,
            kind: p.kind,
            amount: Number(p.amount),
            tip: Number(p.tip),
            platformFee: p.platformFee ? Number(p.platformFee) : null,
            driverPayout: p.driverPayout ? Number(p.driverPayout) : null,
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
