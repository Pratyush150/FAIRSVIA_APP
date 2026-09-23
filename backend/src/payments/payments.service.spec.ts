import { BadGatewayException, BadRequestException, ConflictException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma, TripStatus } from '@prisma/client';
import { PaymentsService } from './payments.service';
import { MockPaymentProvider } from './mock-payment.provider';
import {
  PaymentProvider,
  ProviderRejectedException,
} from './payment-provider.interface';
import { signStripePayload } from './stripe-webhook.util';

/**
 * Focused on the money math: the platform-fee / driver-payout split on
 * capture, the tip flow (100% to the driver), and cancellation fees. Prisma
 * and the gateway are mocked so this stays a fast pure-logic test.
 */
describe('PaymentsService', () => {
  const config = {
    get: (k: string) => {
      if (k === 'platformFeePercent') return 0.2;
      if (k === 'stripeSecretKey') return undefined;
      if (k === 'stripePublishableKey') return 'pk_test_x';
      if (k === 'stripeWebhookSecret') return 'whsec_test_123';
      return undefined;
    },
  } as unknown as ConfigService;

  function makePrisma(overrides: Record<string, unknown> = {}) {
    const prisma: any = {
      trip: {
        findUnique: jest.fn(),
      },
      payment: {
        findUnique: jest.fn(),
        upsert: jest.fn(),
        update: jest.fn(),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      paymentMethod: {
        findFirst: jest.fn().mockResolvedValue(null),
        findUnique: jest.fn().mockResolvedValue(null),
        update: jest.fn().mockResolvedValue({}),
      },
      paymentRefund: {
        create: jest.fn().mockResolvedValue({ id: 'ref_1' }),
        update: jest.fn().mockResolvedValue({}),
      },
      // ensureCustomer reads/writes the user; default to a rider that already
      // has a Stripe customer so charge paths don't try to create one.
      user: {
        findUnique: jest
          .fn()
          .mockResolvedValue({ id: 'r1', phone: '+15550000000', stripeCustomerId: 'cus_test' }),
        update: jest.fn().mockResolvedValue({}),
      },
      driverProfile: {
        findUnique: jest.fn().mockResolvedValue(null),
        update: jest.fn().mockResolvedValue({}),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      webhookEvent: {
        create: jest.fn().mockResolvedValue({}),
      },
      tripEvent: {
        findFirst: jest.fn().mockResolvedValue(null),
      },
      ledgerEntry: {
        create: jest.fn().mockResolvedValue({}),
      },
      ...overrides,
    };
    // refund + webhook now run inside a transaction; the mock runs the callback
    // against the same fake client.
    prisma.$transaction = jest.fn((cb: any) => cb(prisma));
    return prisma as never;
  }

  const ledger = {
    record: jest.fn().mockResolvedValue(null),
    balance: jest.fn().mockResolvedValue(100),
    withdraw: jest
      .fn()
      .mockResolvedValue({ withdrawn: 20, balance: 80 }),
  };

  const queue = { add: jest.fn().mockResolvedValue(undefined) };

  /** Every kill switch off, i.e. normal operation. */
  const flagsAllOff = { isOn: jest.fn().mockResolvedValue(false) };

  function makeService(prisma: never, provider?: PaymentProvider) {
    return new PaymentsService(
      prisma,
      config,
      ledger as never,
      provider ?? new MockPaymentProvider(),
      queue as never,
      flagsAllOff as never,
    );
  }

  /** A fully-mocked provider; override individual calls per test. */
  function makeProvider(overrides: Partial<PaymentProvider> = {}): PaymentProvider {
    return {
      authorize: jest.fn(),
      capture: jest.fn(),
      charge: jest.fn().mockResolvedValue({ intentId: 'ch_x', status: 'captured' }),
      refund: jest.fn().mockResolvedValue('re_x'),
      createCustomer: jest.fn().mockResolvedValue('cus_test'),
      createSetupIntent: jest.fn(),
      listCards: jest.fn().mockResolvedValue([]),
      createConnectAccount: jest.fn().mockResolvedValue('acct_test'),
      createAccountLink: jest.fn().mockResolvedValue('https://onboard'),
      getAccount: jest.fn().mockResolvedValue({
        payoutsEnabled: true,
        detailsSubmitted: true,
        chargesEnabled: true,
      }),
      needsSavedCard: false,
      createTransfer: jest.fn().mockResolvedValue('tr_test'),
      ...overrides,
    } as PaymentProvider;
  }

  it('splits captured fare into a 20% platform fee and 80% payout', async () => {
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      currency: 'USD',
      fareFinal: 100,
      fareEstimate: 100,
    });
    (prisma as any).payment.findUnique.mockResolvedValue({
      externalIntentId: 'mock_pi_x',
      status: 'authorized',
    });
    (prisma as any).payment.update.mockResolvedValue({});

    const capture = jest
      .fn()
      .mockResolvedValue({ intentId: 'mock_pi_x', status: 'captured' });
    const provider = {
      authorize: jest.fn(),
      capture,
      charge: jest.fn(),
      refund: jest.fn(),
      createCustomer: jest.fn().mockResolvedValue('cus_test'),
      createSetupIntent: jest.fn(),
      listCards: jest.fn().mockResolvedValue([]),
      createConnectAccount: jest.fn().mockResolvedValue('acct_test'),
      createAccountLink: jest.fn().mockResolvedValue('https://onboard'),
      getAccount: jest.fn().mockResolvedValue({
        payoutsEnabled: true,
        detailsSubmitted: true,
        chargesEnabled: true,
      }),
      needsSavedCard: false,
      createTransfer: jest.fn().mockResolvedValue('tr_test'),
    } as PaymentProvider;

    const svc = makeService(prisma, provider);
    const split = await svc.captureForTrip('t1');

    expect(split).toEqual({
      fareFinal: 100,
      platformFee: 20,
      driverPayout: 80,
    });
    // Third arg is the capture idempotency key (undefined here — no key on the
    // existing hold in this fixture).
    expect(capture).toHaveBeenCalledWith('mock_pi_x', 100, undefined);
    // Settled through the status-guarded update, in the same transaction as
    // the driver's ledger credit.
    expect((prisma as any).payment.updateMany).toHaveBeenCalledWith({
      where: {
        tripId: 't1',
        status: { notIn: ['captured', 'collected', 'refunded', 'partial'] },
      },
      data: {
        status: 'captured',
        amount: 100,
        platformFee: 20,
        driverPayout: 80,
      },
    });
  });

  it('a capture that loses the settle race books nothing and returns the stored split', async () => {
    ledger.record.mockClear();
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1', riderId: 'r1', driverId: 'd1', fareFinal: 100, fareEstimate: 100,
      currency: 'USD', paymentMode: 'card',
    });
    (prisma as any).payment.findUnique
      .mockResolvedValueOnce({ tripId: 't1', status: 'authorized', amount: 100, externalIntentId: 'pi_1' })
      .mockResolvedValueOnce({ tripId: 't1', status: 'captured', amount: 100, platformFee: 20, driverPayout: 80 });
    (prisma as any).payment.updateMany.mockResolvedValueOnce({ count: 0 });
    const svc = makeService(prisma, makeProvider({
      capture: jest.fn().mockResolvedValue({ intentId: 'pi_1', status: 'captured' }),
    }));

    const split = await svc.captureForTrip('t1');

    expect(ledger.record).not.toHaveBeenCalled();
    expect(split).toEqual({ fareFinal: 100, platformFee: 20, driverPayout: 80 });
  });

  it('rounds the split to two decimals', async () => {
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      currency: 'USD',
      fareFinal: 99.99,
      fareEstimate: 99.99,
    });
    (prisma as any).payment.findUnique.mockResolvedValue({
      externalIntentId: 'mock_pi_x',
      status: 'authorized',
    });
    (prisma as any).payment.update.mockResolvedValue({});

    const provider = {
      authorize: jest.fn(),
      capture: jest.fn().mockResolvedValue({ status: 'captured' }),
      charge: jest.fn(),
      refund: jest.fn(),
      createCustomer: jest.fn().mockResolvedValue('cus_test'),
      createSetupIntent: jest.fn(),
      listCards: jest.fn().mockResolvedValue([]),
      createConnectAccount: jest.fn().mockResolvedValue('acct_test'),
      createAccountLink: jest.fn().mockResolvedValue('https://onboard'),
      getAccount: jest.fn().mockResolvedValue({
        payoutsEnabled: true,
        detailsSubmitted: true,
        chargesEnabled: true,
      }),
      needsSavedCard: false,
      createTransfer: jest.fn().mockResolvedValue('tr_test'),
    } as PaymentProvider;

    const svc = makeService(prisma, provider);
    const split = await svc.captureForTrip('t1');

    // 99.99 * 0.2 = 19.998 → 20.00; payout 99.99 - 20 = 79.99
    expect(split.platformFee).toBe(20);
    expect(split.driverPayout).toBe(79.99);
  });

  it('charges directly when no prior hold exists', async () => {
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      currency: 'USD',
      fareFinal: 50,
      fareEstimate: 50,
    });
    (prisma as any).payment.findUnique.mockResolvedValue(null);
    (prisma as any).payment.upsert.mockResolvedValue({});
    (prisma as any).payment.update.mockResolvedValue({});

    const charge = jest
      .fn()
      .mockResolvedValue({ intentId: 'mock_ch_y', status: 'captured' });
    const provider = {
      authorize: jest.fn(),
      capture: jest.fn(),
      charge,
      refund: jest.fn(),
      createCustomer: jest.fn().mockResolvedValue('cus_test'),
      createSetupIntent: jest.fn(),
      listCards: jest.fn().mockResolvedValue([]),
      createConnectAccount: jest.fn().mockResolvedValue('acct_test'),
      createAccountLink: jest.fn().mockResolvedValue('https://onboard'),
      getAccount: jest.fn().mockResolvedValue({
        payoutsEnabled: true,
        detailsSubmitted: true,
        chargesEnabled: true,
      }),
      needsSavedCard: false,
      createTransfer: jest.fn().mockResolvedValue('tr_test'),
    } as PaymentProvider;

    const svc = makeService(prisma, provider);
    const split = await svc.captureForTrip('t1');

    expect(charge).toHaveBeenCalled();
    expect(split.platformFee).toBe(10);
    expect(split.driverPayout).toBe(40);
  });

  it('adds a tip fully to the driver payout', async () => {
    ledger.record.mockClear();
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      driverId: 'd1',
      currency: 'USD',
      status: TripStatus.completed,
      paymentMode: 'card',
    });
    (prisma as any).payment.findUnique.mockResolvedValue({
      tip: 0,
      driverPayout: 80,
    });
    // The rider's saved card is what the tip is charged to.
    (prisma as any).paymentMethod.findFirst.mockResolvedValue({
      id: 'pm_1',
      userId: 'r1',
      externalId: 'pm_ext_1',
      isDefault: true,
    });
    const provider = makeProvider();

    const svc = makeService(prisma, provider);
    const res = await svc.addTip('r1', 't1', 15);

    expect(res).toEqual({ tip: 15, driverPayout: 95, paymentMode: 'card' });
    expect(provider.charge).toHaveBeenCalledWith(
      expect.objectContaining({
        amount: 15,
        methodRef: 'pm_ext_1',
        idempotencyKey: 'tip-t1',
      }),
    );
    // Guarded increment: only applies while the trip has no tip yet.
    expect((prisma as any).payment.updateMany).toHaveBeenCalledWith({
      where: { tripId: 't1', tip: 0 },
      data: { tip: { increment: 15 }, driverPayout: { increment: 15 } },
    });
    expect(ledger.record).toHaveBeenCalledWith('d1', 'tip', 15, expect.anything(), expect.anything());
  });

  it('with a real processor, refuses a card tip it cannot charge — and credits nobody', async () => {
    ledger.record.mockClear();
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1', riderId: 'r1', driverId: 'd1', currency: 'USD',
      status: TripStatus.completed, paymentMode: 'card',
    });
    (prisma as any).payment.findUnique.mockResolvedValue({ tip: 0, driverPayout: 80 });
    (prisma as any).paymentMethod.findFirst.mockResolvedValue(null);
    const provider = { ...makeProvider(), needsSavedCard: true };
    await expect(makeService(prisma, provider).addTip('r1', 't1', 5)).rejects.toThrow(
      BadRequestException,
    );
    expect(provider.charge).not.toHaveBeenCalled();
    expect((prisma as any).payment.updateMany).not.toHaveBeenCalled();
    expect(ledger.record).not.toHaveBeenCalled();
  });

  it('with the mock provider, records a card-ride tip when no card is saved', async () => {
    // The mock stands in for an always-present card (dev and tests).
    ledger.record.mockClear();
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1', riderId: 'r1', driverId: 'd1', currency: 'USD',
      status: TripStatus.completed, paymentMode: 'card',
    });
    (prisma as any).payment.findUnique.mockResolvedValue({ tip: 0, driverPayout: 80 });
    (prisma as any).paymentMethod.findFirst.mockResolvedValue(null);
    const provider = makeProvider();
    const res = await makeService(prisma, provider).addTip('r1', 't1', 5);
    expect(res).toEqual({ tip: 5, driverPayout: 85, paymentMode: 'card' });
    expect(provider.charge).not.toHaveBeenCalled();
    expect(ledger.record).toHaveBeenCalledWith('d1', 'tip', 5, expect.anything(), expect.anything());
  });

  it('a cash-ride tip is recorded to the driver with no card charge', async () => {
    ledger.record.mockClear();
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1', riderId: 'r1', driverId: 'd1', currency: 'USD',
      status: TripStatus.completed, paymentMode: 'cash',
    });
    (prisma as any).payment.findUnique.mockResolvedValue({ tip: 0, driverPayout: 80 });
    const provider = makeProvider();
    const res = await makeService(prisma, provider).addTip('r1', 't1', 3);
    expect(res).toEqual({ tip: 3, driverPayout: 83, paymentMode: 'cash' });
    expect(provider.charge).not.toHaveBeenCalled();
    // Cash is already in the driver's hand: nothing to credit on the ledger.
    expect(ledger.record).not.toHaveBeenCalledWith('d1', 'tip', 3, expect.anything());
  });

  it('rejects a second tip on the same trip with 409 (no double charge / credit)', async () => {
    ledger.record.mockClear();
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      driverId: 'd1',
      currency: 'USD',
      status: TripStatus.completed,
      paymentMode: 'card',
    });
    (prisma as any).payment.findUnique.mockResolvedValue({ tip: 15, driverPayout: 95 });
    const provider = makeProvider();

    const svc = makeService(prisma, provider);
    await expect(svc.addTip('r1', 't1', 10)).rejects.toThrow(ConflictException);
    expect(provider.charge).not.toHaveBeenCalled();
    expect((prisma as any).payment.updateMany).not.toHaveBeenCalled();
    expect(ledger.record).not.toHaveBeenCalled();
  });

  it('409s when a concurrent tip won the guarded increment', async () => {
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      driverId: 'd1',
      currency: 'USD',
      status: TripStatus.completed,
      paymentMode: 'card',
    });
    (prisma as any).payment.findUnique.mockResolvedValue({ tip: 0, driverPayout: 80 });
    (prisma as any).payment.updateMany.mockResolvedValue({ count: 0 });
    const svc = makeService(prisma, makeProvider());
    await expect(svc.addTip('r1', 't1', 10)).rejects.toThrow(ConflictException);
  });

  it('records a cash tip without charging a card or crediting the ledger', async () => {
    ledger.record.mockClear();
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      driverId: 'd1',
      currency: 'USD',
      status: TripStatus.completed,
      paymentMode: 'cash',
    });
    (prisma as any).payment.findUnique.mockResolvedValue({ tip: 0, driverPayout: 80 });
    const provider = makeProvider();

    const svc = makeService(prisma, provider);
    const res = await svc.addTip('r1', 't1', 5);

    expect(res).toEqual({ tip: 5, driverPayout: 85, paymentMode: 'cash' });
    expect(provider.charge).not.toHaveBeenCalled();
    expect((prisma as any).payment.updateMany).toHaveBeenCalled();
    expect(ledger.record).not.toHaveBeenCalled(); // cash is already in hand
  });

  it('rejects a tip from someone who is not the rider', async () => {
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      currency: 'USD',
    });
    const svc = makeService(prisma);
    await expect(svc.addTip('someone-else', 't1', 15)).rejects.toThrow(
      'Only the rider can tip',
    );
  });

  it('charges the cancellation fee and records it as a cancellation payment', async () => {
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      currency: 'USD',
    });
    (prisma as any).payment.upsert.mockResolvedValue({});

    const charge = jest
      .fn()
      .mockResolvedValue({ intentId: 'mock_ch_c', status: 'captured' });
    const provider = {
      authorize: jest.fn(),
      capture: jest.fn(),
      charge,
      refund: jest.fn(),
      createCustomer: jest.fn().mockResolvedValue('cus_test'),
      createSetupIntent: jest.fn(),
      listCards: jest.fn().mockResolvedValue([]),
      createConnectAccount: jest.fn().mockResolvedValue('acct_test'),
      createAccountLink: jest.fn().mockResolvedValue('https://onboard'),
      getAccount: jest.fn().mockResolvedValue({
        payoutsEnabled: true,
        detailsSubmitted: true,
        chargesEnabled: true,
      }),
      needsSavedCard: false,
      createTransfer: jest.fn().mockResolvedValue('tr_test'),
    } as PaymentProvider;

    const svc = makeService(prisma, provider);
    const fee = await svc.chargeCancellationFee('t1', 30);

    expect(fee).toBe(30);
    expect(charge).toHaveBeenCalled();
    const upsertArg = (prisma as any).payment.upsert.mock.calls[0][0];
    expect(upsertArg.create.kind).toBe('cancellation');
    expect(upsertArg.create.platformFee).toBe(6);
    expect(upsertArg.create.driverPayout).toBe(24);
  });

  it('records a cash-trip cancellation fee as owed with no card charge', async () => {
    ledger.record.mockClear();
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      driverId: 'd1',
      currency: 'USD',
      paymentMode: 'cash',
    });
    (prisma as any).payment.upsert.mockResolvedValue({});
    const provider = makeProvider();

    const svc = makeService(prisma, provider);
    const fee = await svc.chargeCancellationFee('t1', 5);

    expect(fee).toBe(5);
    expect(provider.charge).not.toHaveBeenCalled();
    const upsertArg = (prisma as any).payment.upsert.mock.calls[0][0];
    expect(upsertArg.create).toEqual(
      expect.objectContaining({ kind: 'cancellation', method: 'cash', status: 'pending' }),
    );
    expect(ledger.record).not.toHaveBeenCalled(); // nothing collected yet
  });

  it('uses a stable per-trip idempotency key for the card cancellation fee', async () => {
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      currency: 'USD',
      paymentMode: 'card',
    });
    (prisma as any).payment.upsert.mockResolvedValue({});
    const provider = makeProvider();
    await makeService(prisma, provider).chargeCancellationFee('t1', 5);
    expect(provider.charge).toHaveBeenCalledWith(
      expect.objectContaining({ idempotencyKey: 'cancel-fee-t1' }),
    );
  });

  it('charges the card the rider chose for the trip, not the default', async () => {
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      currency: 'USD',
      fareEstimate: 25,
      paymentMode: 'card',
      paymentMethodId: 'pm_row_chosen',
    });
    (prisma as any).payment.findUnique.mockResolvedValue(null);
    (prisma as any).payment.upsert.mockResolvedValue({});
    (prisma as any).paymentMethod.findFirst.mockImplementation(
      async ({ where }: any) =>
        where.id === 'pm_row_chosen' && where.userId === 'r1'
          ? { id: 'pm_row_chosen', externalId: 'pm_chosen' }
          : { id: 'pm_row_default', externalId: 'pm_default' },
    );
    const provider = makeProvider({
      authorize: jest.fn().mockResolvedValue({ intentId: 'pi_1', status: 'authorized' }),
    });

    await makeService(prisma, provider).authorizeForTrip('t1');

    expect(provider.authorize).toHaveBeenCalledWith(
      expect.objectContaining({ methodRef: 'pm_chosen' }),
    );
    expect((prisma as any).paymentMethod.findFirst).toHaveBeenCalledWith({
      where: { id: 'pm_row_chosen', userId: 'r1' },
    });
  });

  it('falls back to the default card when the chosen one no longer exists', async () => {
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      currency: 'USD',
      fareEstimate: 25,
      paymentMode: 'card',
      paymentMethodId: 'pm_row_gone',
    });
    (prisma as any).payment.findUnique.mockResolvedValue(null);
    (prisma as any).payment.upsert.mockResolvedValue({});
    (prisma as any).paymentMethod.findFirst.mockImplementation(
      async ({ where }: any) =>
        where.isDefault ? { id: 'pm_row_default', externalId: 'pm_default' } : null,
    );
    const provider = makeProvider({
      authorize: jest.fn().mockResolvedValue({ intentId: 'pi_1', status: 'authorized' }),
    });
    await makeService(prisma, provider).authorizeForTrip('t1');
    expect(provider.authorize).toHaveBeenCalledWith(
      expect.objectContaining({ methodRef: 'pm_default' }),
    );
  });

  it('enqueues a durable capture retry keyed to the trip', async () => {
    queue.add.mockClear();
    const svc = makeService(makePrisma());
    await svc.enqueueCapture('t1');
    expect(queue.add).toHaveBeenCalledWith(
      expect.any(String),
      { tripId: 't1' },
      expect.objectContaining({ jobId: 'capture-t1', attempts: expect.any(Number) }),
    );
  });

  it('is a no-op cancellation fee when amount is zero', async () => {
    const prisma = makePrisma();
    const svc = makeService(prisma);
    await expect(svc.chargeCancellationFee('t1', 0)).resolves.toBe(0);
    expect((prisma as any).trip.findUnique).not.toHaveBeenCalled();
  });

  it('partially refunds a captured payment and claws back the driver share', async () => {
    ledger.record.mockClear();
    const prisma = makePrisma();
    (prisma as any).payment.findUnique.mockResolvedValue({
      status: 'captured',
      amount: 100,
      refundedAmount: 0,
      externalIntentId: 'mock_pi_x',
    });
    (prisma as any).trip.findUnique.mockResolvedValue({ driverId: 'd1' });
    (prisma as any).payment.update.mockResolvedValue({});
    const refund = jest.fn().mockResolvedValue(undefined);
    const provider = {
      authorize: jest.fn(),
      capture: jest.fn(),
      charge: jest.fn(),
      refund,
      createCustomer: jest.fn().mockResolvedValue('cus_test'),
      createSetupIntent: jest.fn(),
      listCards: jest.fn().mockResolvedValue([]),
      createConnectAccount: jest.fn().mockResolvedValue('acct_test'),
      createAccountLink: jest.fn().mockResolvedValue('https://onboard'),
      getAccount: jest.fn().mockResolvedValue({
        payoutsEnabled: true,
        detailsSubmitted: true,
        chargesEnabled: true,
      }),
      needsSavedCard: false,
      createTransfer: jest.fn().mockResolvedValue('tr_test'),
    } as PaymentProvider;

    const svc = makeService(prisma, provider);
    const res = await svc.refundTrip('t1', 40, 'complaint');

    expect(res).toEqual({
      tripId: 't1',
      refundId: 'ref_1',
      refunded: 40,
      totalRefunded: 40,
      status: 'partial',
    });
    // Provider is keyed on the committed refund record's id.
    expect(refund).toHaveBeenCalledWith('mock_pi_x', 40, 'refund-ref_1');
    // Record-first: the pending row is committed before the provider call,
    // then flipped to succeeded with the provider's refund id.
    const createOrder = (prisma as any).paymentRefund.create.mock.invocationCallOrder[0];
    const refundOrder = refund.mock.invocationCallOrder[0];
    expect(createOrder).toBeLessThan(refundOrder);
    expect((prisma as any).paymentRefund.create.mock.calls[0][0].data).toEqual(
      expect.objectContaining({ tripId: 't1', amount: 40, status: 'pending' }),
    );
    expect((prisma as any).paymentRefund.update).toHaveBeenCalledWith({
      where: { id: 'ref_1' },
      data: { status: 'succeeded', externalRefundId: null },
    });
    // Driver clawback = 40 * (1 - 0.2) = 32, recorded in the same transaction.
    expect((prisma as any).ledgerEntry.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        driverId: 'd1',
        type: 'adjustment',
        amount: -32,
        tripId: 't1',
      }),
    });
  });

  it('marks a payment fully refunded when the whole amount is returned', async () => {
    const prisma = makePrisma();
    (prisma as any).payment.findUnique.mockResolvedValue({
      status: 'captured',
      amount: 100,
      refundedAmount: 0,
      externalIntentId: 'mock_pi_x',
    });
    (prisma as any).trip.findUnique.mockResolvedValue({ driverId: null });
    const update = jest.fn().mockResolvedValue({});
    (prisma as any).payment.update = update;

    const svc = makeService(prisma);
    const res = await svc.refundTrip('t1'); // full remaining
    expect(res.refunded).toBe(100);
    expect(res.status).toBe('refunded');
    expect(update.mock.calls[0][0].data.status).toBe('refunded');
  });

  it('marks the refund failed and reverses the reservation when the provider rejects it', async () => {
    const prisma = makePrisma();
    (prisma as any).payment.findUnique.mockResolvedValue({
      id: 'pay_1',
      status: 'captured',
      amount: 100,
      refundedAmount: 0,
      externalIntentId: 'mock_pi_x',
    });
    (prisma as any).trip.findUnique.mockResolvedValue({ driverId: 'd1' });
    (prisma as any).payment.update.mockResolvedValue({});
    const provider = makeProvider({
      refund: jest.fn().mockRejectedValue(new Error('stripe down')),
    });

    const svc = makeService(prisma, provider);
    await expect(svc.refundTrip('t1', 40, 'complaint')).rejects.toThrow(/Nothing was refunded/);

    expect((prisma as any).paymentRefund.update).toHaveBeenCalledWith({
      where: { id: 'ref_1' },
      data: expect.objectContaining({ status: 'failed', failureMessage: 'stripe down' }),
    });
    // The reserved amount is handed back and the clawback reversed.
    expect((prisma as any).payment.update).toHaveBeenLastCalledWith({
      where: { tripId: 't1' },
      data: { refundedAmount: { decrement: 40 }, status: 'captured' },
    });
    expect((prisma as any).ledgerEntry.create).toHaveBeenLastCalledWith({
      data: expect.objectContaining({ driverId: 'd1', type: 'adjustment', amount: 32 }),
    });
  });

  it('never calls the provider when a concurrent refund wins the serializable reservation', async () => {
    const prisma = makePrisma();
    (prisma as any).$transaction = jest.fn().mockRejectedValue(
      new Prisma.PrismaClientKnownRequestError('conflict', {
        code: 'P2034',
        clientVersion: 'x',
      }),
    );
    const provider = makeProvider();
    await expect(makeService(prisma, provider).refundTrip('t1', 10)).rejects.toThrow(
      /try again/i,
    );
    expect(provider.refund).not.toHaveBeenCalled();
  });

  it('rejects over-refunding beyond the remaining balance', async () => {
    const prisma = makePrisma();
    (prisma as any).payment.findUnique.mockResolvedValue({
      status: 'captured',
      amount: 100,
      refundedAmount: 80,
      externalIntentId: 'mock_pi_x',
    });
    const svc = makeService(prisma);
    // Only 20 remains refundable.
    await expect(svc.refundTrip('t1', 50)).rejects.toThrow(/between 0 and/);
  });

  it('creates a Stripe customer on first setup-intent and returns sheet secrets', async () => {
    const prisma = makePrisma();
    (prisma as any).user.findUnique.mockResolvedValue({
      id: 'r1',
      phone: '+15551112222',
      email: 'r@x.com',
      fullName: 'Rider One',
      stripeCustomerId: null, // no customer yet
    });
    const createCustomer = jest.fn().mockResolvedValue('cus_new');
    const createSetupIntent = jest.fn().mockResolvedValue({
      id: 'seti_1',
      clientSecret: 'seti_1_secret',
      customerRef: 'cus_new',
      ephemeralKeySecret: 'ek_secret',
    });
    const provider = {
      authorize: jest.fn(),
      capture: jest.fn(),
      charge: jest.fn(),
      refund: jest.fn(),
      createCustomer,
      createSetupIntent,
      listCards: jest.fn().mockResolvedValue([]),
      createConnectAccount: jest.fn().mockResolvedValue('acct_test'),
      createAccountLink: jest.fn().mockResolvedValue('https://onboard'),
      getAccount: jest.fn().mockResolvedValue({
        payoutsEnabled: true,
        detailsSubmitted: true,
        chargesEnabled: true,
      }),
      needsSavedCard: false,
      createTransfer: jest.fn().mockResolvedValue('tr_test'),
    } as PaymentProvider;

    const svc = makeService(prisma, provider);
    const res = await svc.createSetupIntent('r1');

    expect(createCustomer).toHaveBeenCalledWith(
      expect.objectContaining({ userId: 'r1', email: 'r@x.com', name: 'Rider One' }),
    );
    // The new customer id is persisted so it's reused next time.
    expect((prisma as any).user.update).toHaveBeenCalledWith({
      where: { id: 'r1' },
      data: { stripeCustomerId: 'cus_new' },
    });
    expect(res).toEqual({
      setupIntentClientSecret: 'seti_1_secret',
      customerId: 'cus_new',
      ephemeralKeySecret: 'ek_secret',
      publishableKey: 'pk_test_x',
    });
  });

  it('stamps an idempotency key on the trip auth-hold and passes it to the provider', async () => {
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      currency: 'USD',
      fareEstimate: 25,
      paymentMode: 'card',
    });
    (prisma as any).payment.findUnique.mockResolvedValue(null); // no prior key
    (prisma as any).payment.upsert.mockResolvedValue({});
    const authorize = jest
      .fn()
      .mockResolvedValue({ intentId: 'pi_1', status: 'authorized' });
    const provider = {
      authorize,
      capture: jest.fn(),
      charge: jest.fn(),
      refund: jest.fn(),
      createCustomer: jest.fn().mockResolvedValue('cus_test'),
      createSetupIntent: jest.fn(),
      listCards: jest.fn().mockResolvedValue([]),
      createConnectAccount: jest.fn().mockResolvedValue('acct_test'),
      createAccountLink: jest.fn().mockResolvedValue('https://onboard'),
      getAccount: jest.fn().mockResolvedValue({
        payoutsEnabled: true,
        detailsSubmitted: true,
        chargesEnabled: true,
      }),
      needsSavedCard: false,
      createTransfer: jest.fn().mockResolvedValue('tr_test'),
    } as PaymentProvider;

    const svc = makeService(prisma, provider);
    await svc.authorizeForTrip('t1');

    const idem = authorize.mock.calls[0][0].idempotencyKey;
    expect(typeof idem).toBe('string');
    expect(idem.length).toBeGreaterThan(0);
    // Same key is persisted on the payment row so a retry reuses it.
    expect((prisma as any).payment.upsert.mock.calls[0][0].create.idempotencyKey).toBe(idem);
  });

  it('syncs the provider cards into the local payment methods', async () => {
    const prisma = makePrisma();
    (prisma as any).paymentMethod.count = jest.fn().mockResolvedValue(0);
    (prisma as any).paymentMethod.create = jest.fn().mockResolvedValue({});
    (prisma as any).paymentMethod.findMany = jest
      .fn()
      .mockResolvedValue([{ id: 'm1', externalId: 'pm_1' }]);
    const provider = {
      authorize: jest.fn(),
      capture: jest.fn(),
      charge: jest.fn(),
      refund: jest.fn(),
      createCustomer: jest.fn().mockResolvedValue('cus_test'),
      createSetupIntent: jest.fn(),
      listCards: jest
        .fn()
        .mockResolvedValue([{ ref: 'pm_1', brand: 'visa', last4: '4242' }]),
      createConnectAccount: jest.fn().mockResolvedValue('acct_test'),
      createAccountLink: jest.fn().mockResolvedValue('https://onboard'),
      getAccount: jest.fn().mockResolvedValue({
        payoutsEnabled: true,
        detailsSubmitted: true,
        chargesEnabled: true,
      }),
      needsSavedCard: false,
      createTransfer: jest.fn().mockResolvedValue('tr_test'),
    } as PaymentProvider;

    const svc = makeService(prisma, provider);
    const methods = await svc.syncMethods('r1');

    const createArg = (prisma as any).paymentMethod.create.mock.calls[0][0];
    expect(createArg.data).toEqual(
      expect.objectContaining({
        userId: 'r1',
        externalId: 'pm_1',
        brand: 'visa',
        last4: '4242',
        isDefault: true, // first card
      }),
    );
    expect(methods).toEqual([{ id: 'm1', externalId: 'pm_1' }]);
  });

  it('opens a Connect account on first onboard and returns a hosted link', async () => {
    const prisma = makePrisma();
    (prisma as any).driverProfile.findUnique.mockResolvedValue({
      userId: 'd1',
      stripeAccountId: null,
    });
    (prisma as any).user.findUnique.mockResolvedValue({
      id: 'd1',
      email: 'd@x.com',
    });
    const createConnectAccount = jest.fn().mockResolvedValue('acct_new');
    const createAccountLink = jest
      .fn()
      .mockResolvedValue('https://connect.stripe.com/onboard/abc');
    const provider = {
      authorize: jest.fn(),
      capture: jest.fn(),
      charge: jest.fn(),
      refund: jest.fn(),
      createCustomer: jest.fn(),
      createSetupIntent: jest.fn(),
      listCards: jest.fn(),
      createConnectAccount,
      createAccountLink,
      getAccount: jest.fn(),
      needsSavedCard: false,
      createTransfer: jest.fn(),
    } as PaymentProvider;

    const svc = makeService(prisma, provider);
    const res = await svc.connectOnboard('d1');

    expect(createConnectAccount).toHaveBeenCalledWith(
      expect.objectContaining({ userId: 'd1', email: 'd@x.com' }),
    );
    expect((prisma as any).driverProfile.update).toHaveBeenCalledWith({
      where: { userId: 'd1' },
      data: { stripeAccountId: 'acct_new' },
    });
    expect(res).toEqual({
      url: 'https://connect.stripe.com/onboard/abc',
      accountId: 'acct_new',
    });
  });

  it('persists payoutsEnabled when Connect status flips to enabled', async () => {
    const prisma = makePrisma();
    (prisma as any).driverProfile.findUnique.mockResolvedValue({
      userId: 'd1',
      stripeAccountId: 'acct_1',
      payoutsEnabled: false,
    });
    const getAccount = jest.fn().mockResolvedValue({
      payoutsEnabled: true,
      detailsSubmitted: true,
      chargesEnabled: true,
    });
    const provider = {
      authorize: jest.fn(),
      capture: jest.fn(),
      charge: jest.fn(),
      refund: jest.fn(),
      createCustomer: jest.fn(),
      createSetupIntent: jest.fn(),
      listCards: jest.fn(),
      createConnectAccount: jest.fn(),
      createAccountLink: jest.fn(),
      getAccount,
      needsSavedCard: false,
      createTransfer: jest.fn(),
    } as PaymentProvider;

    const svc = makeService(prisma, provider);
    const res = await svc.connectStatus('d1');

    expect((prisma as any).driverProfile.update).toHaveBeenCalledWith({
      where: { userId: 'd1' },
      data: { payoutsEnabled: true },
    });
    expect(res).toEqual({
      onboarded: true,
      payoutsEnabled: true,
      detailsSubmitted: true,
    });
  });

  function connectPrisma() {
    const prisma = makePrisma({
      ledgerEntry: {
        create: jest.fn().mockResolvedValue({}),
        update: jest.fn().mockResolvedValue({}),
      },
    });
    (prisma as any).driverProfile.findUnique.mockResolvedValue({
      userId: 'd1',
      stripeAccountId: 'acct_1',
      payoutsEnabled: true,
    });
    return prisma;
  }

  function reverseMock() {
    return ((ledger as any).reverseWithdrawal = jest.fn().mockResolvedValue(null));
  }

  it('pays out via a Connect transfer: reserve first, transfer keyed on the reservation', async () => {
    const prisma = connectPrisma();
    const order: string[] = [];
    ledger.withdraw.mockImplementationOnce(async () => {
      order.push('reserve');
      return { withdrawn: 20, balance: 30, entryId: 'le_1' };
    });
    const createTransfer = jest.fn(async () => {
      order.push('transfer');
      return 'tr_1';
    });
    const svc = makeService(prisma, makeProvider({ createTransfer }));
    const res = await svc.payout('d1', 20);

    // The balance check + debit happen BEFORE money moves, so two concurrent
    // payouts cannot both pass it.
    expect(order).toEqual(['reserve', 'transfer']);
    expect(ledger.withdraw).toHaveBeenCalledWith('d1', 20, 'Payout to bank');
    expect(createTransfer).toHaveBeenCalledWith(
      expect.objectContaining({
        accountId: 'acct_1',
        amount: 20,
        currency: 'USD',
        idempotencyKey: 'payout-le_1',
      }),
    );
    expect((prisma as any).ledgerEntry.update).toHaveBeenCalledWith({
      where: { id: 'le_1' },
      data: { note: 'Payout to bank (tr_1)' },
    });
    expect(res).toEqual({ withdrawn: 20, balance: 30, transferId: 'tr_1', mode: 'stripe' });
  });

  it('a definitively rejected transfer gives the reserved balance back', async () => {
    const prisma = connectPrisma();
    const reverse = reverseMock();
    ledger.withdraw.mockResolvedValueOnce({ withdrawn: 20, balance: 30, entryId: 'le_2' });
    const svc = makeService(prisma, makeProvider({
      needsSavedCard: false,
      createTransfer: jest.fn().mockRejectedValue(
        new ProviderRejectedException('Insufficient funds in platform balance'),
      ),
    }));

    await expect(svc.payout('d1', 20)).rejects.toThrow(ProviderRejectedException);
    expect(reverse).toHaveBeenCalledWith('d1', 20, 'Insufficient funds in platform balance');
  });

  it('a transfer with an unknown outcome keeps the balance reserved and flags it', async () => {
    const prisma = connectPrisma();
    const reverse = reverseMock();
    ledger.withdraw.mockResolvedValueOnce({ withdrawn: 20, balance: 30, entryId: 'le_3' });
    const svc = makeService(prisma, makeProvider({
      needsSavedCard: false,
      createTransfer: jest.fn().mockRejectedValue(
        new BadGatewayException('Stripe unreachable: socket hang up'),
      ),
    }));

    await expect(svc.payout('d1', 20)).rejects.toThrow(BadGatewayException);
    // Reversing here could pay the driver twice if the transfer actually went.
    expect(reverse).not.toHaveBeenCalled();
    expect((prisma as any).ledgerEntry.update).toHaveBeenCalledWith({
      where: { id: 'le_3' },
      data: { note: 'Payout to bank — PENDING RECONCILIATION' },
    });
  });

  it('falls back to a mock withdrawal when payouts are not enabled', async () => {
    const prisma = makePrisma(); // driverProfile.findUnique → null by default
    ledger.withdraw.mockResolvedValueOnce({ withdrawn: 20, balance: 80 });
    const svc = makeService(prisma);
    const res = await svc.payout('d1', 20);

    expect(ledger.withdraw).toHaveBeenCalledWith('d1', 20);
    expect(res).toEqual({
      withdrawn: 20,
      balance: 80,
      transferId: null,
      mode: 'mock',
    });
  });

  const webhookSecret = 'whsec_test_123';

  it('marks the payment captured on a payment_intent.succeeded webhook', async () => {
    const prisma = makePrisma();
    const body = JSON.stringify({
      id: 'evt_ok',
      type: 'payment_intent.succeeded',
      data: { object: { id: 'pi_1' } },
    });
    const sig = signStripePayload(body, webhookSecret);

    const svc = makeService(prisma);
    const res = await svc.handleWebhook(Buffer.from(body), sig);

    expect(res).toEqual({ received: true });
    expect((prisma as any).webhookEvent.create).toHaveBeenCalledWith({
      data: { id: 'evt_ok', type: 'payment_intent.succeeded' },
    });
    expect((prisma as any).payment.updateMany).toHaveBeenCalledWith({
      where: { externalIntentId: 'pi_1' },
      data: { status: 'captured' },
    });
  });

  it('flips payoutsEnabled on an account.updated webhook', async () => {
    const prisma = makePrisma();
    const body = JSON.stringify({
      id: 'evt_acct',
      type: 'account.updated',
      data: { object: { id: 'acct_1', payouts_enabled: true } },
    });
    const sig = signStripePayload(body, webhookSecret);

    const svc = makeService(prisma);
    await svc.handleWebhook(Buffer.from(body), sig);

    expect((prisma as any).driverProfile.updateMany).toHaveBeenCalledWith({
      where: { stripeAccountId: 'acct_1' },
      data: { payoutsEnabled: true },
    });
  });

  it('is idempotent — a duplicate event id is acknowledged, not re-processed', async () => {
    const prisma = makePrisma();
    (prisma as any).webhookEvent.create.mockRejectedValue(
      new Prisma.PrismaClientKnownRequestError('dup', {
        code: 'P2002',
        clientVersion: 'x',
      }),
    );
    const body = JSON.stringify({
      id: 'evt_dup',
      type: 'payment_intent.succeeded',
      data: { object: { id: 'pi_1' } },
    });
    const sig = signStripePayload(body, webhookSecret);

    const svc = makeService(prisma);
    const res = await svc.handleWebhook(Buffer.from(body), sig);

    expect(res).toEqual({ received: true, duplicate: true });
    // Not dispatched — the effect already happened on first delivery.
    expect((prisma as any).payment.updateMany).not.toHaveBeenCalled();
  });

  it('rejects a webhook with a bad signature', async () => {
    const prisma = makePrisma();
    const body = JSON.stringify({ id: 'evt_x', type: 'noop', data: { object: {} } });
    const svc = makeService(prisma);
    await expect(
      svc.handleWebhook(Buffer.from(body), 't=1,v1=deadbeef'),
    ).rejects.toThrow(/signature failed/i);
  });

  it('rejects webhooks when no signing secret is configured', async () => {
    const prisma = makePrisma();
    const noSecretConfig = {
      get: (k: string) => (k === 'platformFeePercent' ? 0.2 : undefined),
    } as unknown as ConfigService;
    const svc = new PaymentsService(
      prisma,
      noSecretConfig,
      ledger as never,
      new MockPaymentProvider(),
      queue as never,
      flagsAllOff as never,
    );
    const body = JSON.stringify({ id: 'e', type: 't', data: { object: {} } });
    await expect(
      svc.handleWebhook(Buffer.from(body), 'sig'),
    ).rejects.toThrow(/not configured/i);
  });

  // GET /payments/:tripId/receipt replays the breakdown persisted on the
  // completion event (TripsService.settleFare) and folds in the tip.
  describe('saved card management', () => {
    it('setDefaultMethod refuses a card the user does not own', async () => {
      const prisma = makePrisma();
      (prisma as any).paymentMethod.findFirst.mockResolvedValue(null);
      const service = makeService(prisma);
      await expect(service.setDefaultMethod('r1', 'pm_x')).rejects.toThrow(
        'Payment method not found',
      );
    });

    it('setDefaultMethod clears the old default and sets the new one', async () => {
      const prisma = makePrisma();
      (prisma as any).paymentMethod.findFirst.mockResolvedValue({
        id: 'pm_2',
        userId: 'r1',
        isDefault: false,
      });
      (prisma as any).paymentMethod.updateMany = jest
        .fn()
        .mockResolvedValue({ count: 1 });
      (prisma as any).paymentMethod.findMany = jest.fn().mockResolvedValue([]);
      const service = makeService(prisma);
      await service.setDefaultMethod('r1', 'pm_2');
      expect((prisma as any).paymentMethod.updateMany).toHaveBeenCalledWith({
        where: { userId: 'r1', isDefault: true },
        data: { isDefault: false },
      });
      expect((prisma as any).paymentMethod.update).toHaveBeenCalledWith({
        where: { id: 'pm_2' },
        data: { isDefault: true },
      });
    });

    it('removeMethod promotes the newest remaining card when the default goes', async () => {
      const prisma = makePrisma();
      (prisma as any).paymentMethod.findFirst
        .mockResolvedValueOnce({ id: 'pm_1', userId: 'r1', isDefault: true })
        .mockResolvedValueOnce({ id: 'pm_2', userId: 'r1', isDefault: false });
      (prisma as any).paymentMethod.delete = jest.fn().mockResolvedValue({});
      const service = makeService(prisma);
      await expect(service.removeMethod('r1', 'pm_1')).resolves.toEqual({
        deleted: true,
      });
      expect((prisma as any).paymentMethod.delete).toHaveBeenCalledWith({
        where: { id: 'pm_1' },
      });
      expect((prisma as any).paymentMethod.update).toHaveBeenCalledWith({
        where: { id: 'pm_2' },
        data: { isDefault: true },
      });
    });

    it('removeMethod leaves the default alone when a non-default card goes', async () => {
      const prisma = makePrisma();
      (prisma as any).paymentMethod.findFirst.mockResolvedValue({
        id: 'pm_3',
        userId: 'r1',
        isDefault: false,
      });
      (prisma as any).paymentMethod.delete = jest.fn().mockResolvedValue({});
      const service = makeService(prisma);
      await service.removeMethod('r1', 'pm_3');
      expect((prisma as any).paymentMethod.update).not.toHaveBeenCalled();
    });
  });

  describe('getReceipt breakdown', () => {
    const trip = {
      id: 't1', riderId: 'r1', driverId: 'd1', status: TripStatus.completed,
      distanceM: 5000, durationS: 600, currency: 'USD', fareFinal: 12, fareEstimate: 11,
      surgeMultiplier: 1.2, promoDiscount: 1, paymentMode: 'card',
      payment: { status: 'captured', kind: 'ride', method: 'card', amount: 12, tip: 2, platformFee: 2.4, driverPayout: 11.6, refundedAmount: 0, refundReason: null },
    };

    it('returns the stored breakdown with the tip merged in', async () => {
      const prisma: any = makePrisma();
      prisma.trip.findUnique.mockResolvedValue(trip);
      prisma.tripEvent.findFirst.mockResolvedValue({
        meta: { breakdown: { baseFare: 2.5, distanceFare: 6, timeFare: 2.4, bookingFee: 1.5, surgeMultiplier: 1.2, promoDiscount: 1, tip: 0 } },
      });
      const receipt = await makeService(prisma as never).getReceipt('r1', 't1');
      expect(prisma.tripEvent.findFirst).toHaveBeenCalledWith(
        expect.objectContaining({ where: { tripId: 't1', toStatus: TripStatus.completed } }),
      );
      expect(receipt.breakdown).toEqual({
        baseFare: 2.5, distanceFare: 6, timeFare: 2.4, bookingFee: 1.5, surgeMultiplier: 1.2, promoDiscount: 1, tip: 2,
        minimumFareAdjustment: 0,
      });
      expect(receipt.fare).toBe(12);
    });

    it('is null for trips completed before breakdowns were persisted', async () => {
      const prisma: any = makePrisma();
      prisma.trip.findUnique.mockResolvedValue(trip);
      const receipt = await makeService(prisma as never).getReceipt('d1', 't1');
      expect(receipt.breakdown).toBeNull();
    });
  });
});

describe('MockPaymentProvider', () => {
  const provider = new MockPaymentProvider();

  it('authorizes with a mock_pi id and authorized status', async () => {
    const r = await provider.authorize({ amount: 10, currency: 'USD' });
    expect(r.intentId).toMatch(/^mock_pi_/);
    expect(r.status).toBe('authorized');
  });

  it('captures to captured status', async () => {
    const r = await provider.capture('mock_pi_x', 10);
    expect(r.status).toBe('captured');
  });

  it('charges with a mock_ch id', async () => {
    const r = await provider.charge({ amount: 5, currency: 'USD' });
    expect(r.intentId).toMatch(/^mock_ch_/);
    expect(r.status).toBe('captured');
  });

  it('rejects non-positive amounts', async () => {
    await expect(
      provider.authorize({ amount: 0, currency: 'USD' }),
    ).rejects.toThrow('greater than zero');
  });
});
