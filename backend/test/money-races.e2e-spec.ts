import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { PaymentsService } from '../src/payments/payments.service';
import { LedgerService } from '../src/ledger/ledger.service';
import { PromoService } from '../src/promo/promo.service';
import { MockPaymentProvider } from '../src/payments/mock-payment.provider';
import { PAYMENT_PROVIDER } from '../src/payments/payment-provider.interface';

/**
 * Money paths under real concurrency, against the real Postgres. Unit tests
 * mock the database and so cannot show that a race is closed; these fire the
 * same operation N times at once and assert money moved exactly once.
 */
describe('Money races (real Postgres)', () => {
  const N = 6;
  let app: INestApplication;
  let prisma: PrismaService;
  let payments: PaymentsService;
  let ledger: LedgerService;
  let promo: PromoService;
  const provider = new MockPaymentProvider();
  const created = { users: [] as string[], promos: [] as string[] };

  const newUser = async (role: 'rider' | 'driver') => {
    const u = await prisma.user.create({
      data: { phone: `+1999${Math.floor(Math.random() * 1e7)}`, role },
    });
    created.users.push(u.id);
    return u.id;
  };

  const completedTrip = async (paymentMode: 'card' | 'cash') => {
    const riderId = await newUser('rider');
    const driverId = await newUser('driver');
    const trip = await prisma.trip.create({
      data: {
        riderId,
        driverId,
        status: 'completed',
        paymentMode,
        pickupLat: 41.3,
        pickupLng: 69.24,
        dropoffLat: 41.31,
        dropoffLng: 69.25,
        fareEstimate: 100,
        fareFinal: 100,
        completedAt: new Date(),
      },
    });
    return { trip, driverId, riderId };
  };

  const ledgerRows = (driverId: string, type: string) =>
    prisma.ledgerEntry.count({ where: { driverId, type } });

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(PAYMENT_PROVIDER)
      .useValue(provider)
      .compile();
    app = moduleRef.createNestApplication();
    await app.init();
    prisma = app.get(PrismaService);
    payments = app.get(PaymentsService);
    ledger = app.get(LedgerService);
    promo = app.get(PromoService);
  });

  afterAll(async () => {
    await prisma.ledgerEntry.deleteMany({ where: { driverId: { in: created.users } } });
    await prisma.promoCode.deleteMany({ where: { id: { in: created.promos } } });
    await prisma.trip.deleteMany({ where: { riderId: { in: created.users } } });
    await prisma.user.deleteMany({ where: { id: { in: created.users } } });
    await app.close();
  });

  it(`card capture fired ${N}x at once credits the driver exactly once`, async () => {
    const { trip, driverId } = await completedTrip('card');
    await prisma.payment.create({
      data: {
        tripId: trip.id,
        amount: 100,
        status: 'authorized',
        externalIntentId: 'mock_pi_race',
      },
    });

    const results = await Promise.allSettled(
      Array.from({ length: N }, () => payments.captureForTrip(trip.id)),
    );

    expect(results.every((r) => r.status === 'fulfilled')).toBe(true);
    expect(await ledgerRows(driverId, 'earning')).toBe(1);
    const p = await prisma.payment.findUnique({ where: { tripId: trip.id } });
    expect(p?.status).toBe('captured');
    expect(Number(p?.driverPayout)).toBe(80);
    expect(await ledger.balance(driverId)).toBe(80);
  });

  it(`cash settle fired ${N}x at once books the commission exactly once`, async () => {
    const { trip, driverId } = await completedTrip('cash');

    const results = await Promise.allSettled(
      Array.from({ length: N }, () => payments.captureForTrip(trip.id)),
    );

    // Concurrent first-time upserts of the payment row may collide on the
    // unique tripId; what matters is that the commission is booked once.
    expect(results.some((r) => r.status === 'fulfilled')).toBe(true);
    expect(await ledgerRows(driverId, 'commission')).toBe(1);
    expect(await ledger.balance(driverId)).toBe(-20);
  });

  it(`a tip sent ${N}x at once is applied and credited exactly once`, async () => {
    const { trip, driverId, riderId } = await completedTrip('card');
    await payments.captureForTrip(trip.id).catch(() => undefined);
    await prisma.payment.upsert({
      where: { tripId: trip.id },
      create: { tripId: trip.id, amount: 100, status: 'captured', driverPayout: 80 },
      update: {},
    });

    const results = await Promise.allSettled(
      Array.from({ length: N }, () => payments.addTip(riderId, trip.id, 5)),
    );

    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    expect(await ledgerRows(driverId, 'tip')).toBe(1);
    const p = await prisma.payment.findUnique({ where: { tripId: trip.id } });
    expect(Number(p?.tip)).toBe(5);
  });

  it(`${N} concurrent bank payouts against one balance send money once`, async () => {
    const driverId = await newUser('driver');
    await prisma.driverProfile.create({
      data: { userId: driverId, stripeAccountId: 'acct_race', payoutsEnabled: true },
    });
    await ledger.record(driverId, 'earning', 100, { note: 'seed' });
    // A real bank transfer takes hundreds of ms. An instant mock lets each
    // call finish before the next reads the balance, which hides the race.
    const transfer = jest
      .spyOn(provider, 'createTransfer')
      .mockImplementation(async () => {
        await new Promise((r) => setTimeout(r, 150));
        return `tr_${randomUUID()}`;
      });

    const results = await Promise.allSettled(
      Array.from({ length: N }, () => payments.payout(driverId, 60)),
    );

    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    expect(transfer).toHaveBeenCalledTimes(1);
    expect(await ledger.balance(driverId)).toBe(40);
    transfer.mockRestore();
    await prisma.driverProfile.delete({ where: { userId: driverId } });
  });

  it(`a single-use promo redeemed ${N}x at once by one rider discounts once`, async () => {
    const riderId = await newUser('rider');
    const code = `RACE${randomUUID().slice(0, 8).toUpperCase()}`;
    const p = await prisma.promoCode.create({
      data: { code, kind: 'flat', value: 10, perUserLimit: 1 },
    });
    created.promos.push(p.id);

    const discounts = await Promise.all(
      Array.from({ length: N }, () => promo.redeem(code, 50, riderId)),
    );

    expect(discounts.filter((d) => d > 0)).toEqual([10]);
    expect(await prisma.promoRedemption.count({ where: { promoId: p.id } })).toBe(1);
  });
});
