import { ConfigService } from '@nestjs/config';
import { PaymentsService } from './payments.service';
import { MockPaymentProvider } from './mock-payment.provider';
import { PaymentProvider } from './payment-provider.interface';

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
      return undefined;
    },
  } as unknown as ConfigService;

  function makePrisma(overrides: Record<string, unknown> = {}) {
    return {
      trip: {
        findUnique: jest.fn(),
      },
      payment: {
        findUnique: jest.fn(),
        upsert: jest.fn(),
        update: jest.fn(),
      },
      paymentMethod: {
        findFirst: jest.fn().mockResolvedValue(null),
      },
      ...overrides,
    } as never;
  }

  const ledger = {
    record: jest.fn().mockResolvedValue(null),
  };

  function makeService(prisma: never, provider?: PaymentProvider) {
    return new PaymentsService(
      prisma,
      config,
      ledger as never,
      provider ?? new MockPaymentProvider(),
    );
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
    } as PaymentProvider;

    const svc = makeService(prisma, provider);
    const split = await svc.captureForTrip('t1');

    expect(split).toEqual({
      fareFinal: 100,
      platformFee: 20,
      driverPayout: 80,
    });
    expect(capture).toHaveBeenCalledWith('mock_pi_x', 100);
    expect((prisma as any).payment.update).toHaveBeenCalledWith({
      where: { tripId: 't1' },
      data: {
        status: 'captured',
        amount: 100,
        platformFee: 20,
        driverPayout: 80,
      },
    });
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
    } as PaymentProvider;

    const svc = makeService(prisma, provider);
    const split = await svc.captureForTrip('t1');

    expect(charge).toHaveBeenCalled();
    expect(split.platformFee).toBe(10);
    expect(split.driverPayout).toBe(40);
  });

  it('adds a tip fully to the driver payout', async () => {
    const prisma = makePrisma();
    (prisma as any).trip.findUnique.mockResolvedValue({
      id: 't1',
      riderId: 'r1',
      currency: 'USD',
    });
    (prisma as any).payment.findUnique.mockResolvedValue({
      tip: 0,
      driverPayout: 80,
    });
    (prisma as any).payment.update.mockResolvedValue({
      tip: 15,
      driverPayout: 95,
    });

    const svc = makeService(prisma);
    const res = await svc.addTip('r1', 't1', 15);

    expect(res).toEqual({ tip: 15, driverPayout: 95 });
    expect((prisma as any).payment.update).toHaveBeenCalledWith({
      where: { tripId: 't1' },
      data: { tip: 15, driverPayout: 95 },
    });
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
    } as PaymentProvider;

    const svc = makeService(prisma, provider);
    const res = await svc.refundTrip('t1', 40, 'complaint');

    expect(res).toEqual({
      tripId: 't1',
      refunded: 40,
      totalRefunded: 40,
      status: 'partial',
    });
    expect(refund).toHaveBeenCalledWith('mock_pi_x', 40);
    // Driver clawback = 40 * (1 - 0.2) = 32.
    expect(ledger.record).toHaveBeenCalledWith(
      'd1',
      'adjustment',
      -32,
      expect.objectContaining({ tripId: 't1' }),
    );
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
