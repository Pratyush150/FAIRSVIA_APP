import {
  BadRequestException,
  ForbiddenException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
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

    const [customerRef, existing, method] = await Promise.all([
      this.ensureCustomer(trip.riderId),
      this.prisma.payment.findUnique({ where: { tripId } }),
      this.defaultMethod(trip.riderId),
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
      await this.provider.capture(
        existing.externalIntentId,
        final,
        existing.idempotencyKey ? `${existing.idempotencyKey}-cap` : undefined,
      );
    } else if (final > 0) {
      const [customerRef, method] = await Promise.all([
        this.ensureCustomer(trip.riderId),
        this.defaultMethod(trip.riderId),
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
      await this.prisma.payment.upsert({
        where: { tripId },
        create: {
          tripId,
          amount: final,
          currency: trip.currency,
          status: 'captured',
          kind: 'ride',
          externalIntentId: intent.intentId,
          idempotencyKey,
        },
        update: { externalIntentId: intent.intentId, idempotencyKey },
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

    const [customerRef, method] = await Promise.all([
      this.ensureCustomer(trip.riderId),
      this.defaultMethod(trip.riderId),
    ]);
    const intent = await this.provider.charge({
      amount,
      currency: trip.currency,
      customerRef,
      methodRef: method?.externalId ?? undefined,
      description: `Cancellation fee ${tripId}`,
      idempotencyKey: randomUUID(),
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
        `Refund must be between 0 and $${remaining.toFixed(2)}`,
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

    const [customerRef, method] = await Promise.all([
      this.ensureCustomer(userId),
      this.defaultMethod(userId),
    ]);
    await this.provider.charge({
      amount,
      currency: trip.currency,
      customerRef,
      methodRef: method?.externalId ?? undefined,
      description: `Tip ${tripId}`,
      idempotencyKey: randomUUID(),
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
    const profile = await this.prisma.driverProfile.findUnique({
      where: { userId },
    });
    if (profile?.stripeAccountId && profile.payoutsEnabled) {
      const requested = round2(amount);
      if (requested <= 0) {
        throw new BadRequestException('Enter an amount greater than zero.');
      }
      const balance = await this.ledger.balance(userId);
      if (requested > balance) {
        throw new BadRequestException(
          `You can withdraw up to $${balance.toFixed(2)}.`,
        );
      }
      const transferId = await this.provider.createTransfer({
        accountId: profile.stripeAccountId,
        amount: requested,
        currency: 'USD',
        idempotencyKey: randomUUID(),
      });
      await this.ledger.record(userId, 'withdrawal', -requested, {
        note: `Payout to bank (${transferId})`,
      });
      return {
        withdrawn: requested,
        balance: round2(balance - requested),
        transferId,
        mode: 'stripe' as const,
      };
    }
    // No Connect payouts yet — simulated withdrawal.
    const res = await this.ledger.withdraw(userId, amount);
    return { ...res, transferId: null, mode: 'mock' as const };
  }

  /**
   * Return the rider's provider customer ref, creating (and persisting) one on
   * first use. Charges/holds reference this — never the raw UberNav user id.
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
}
