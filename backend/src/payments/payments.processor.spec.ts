import { TripStatus } from '@prisma/client';
import { Job } from 'bullmq';
import { PaymentsProcessor } from './payments.processor';

/**
 * The durable capture-retry worker: settles a completed trip's fare after the
 * capture at completion failed, emits the REAL split only once it lands, and
 * flags the trip payment_failed when every attempt is spent.
 */
describe('PaymentsProcessor', () => {
  function build(tripStatus: TripStatus | null = TripStatus.completed) {
    const trip =
      tripStatus === null
        ? null
        : {
            id: 't1',
            riderId: 'r1',
            driverId: 'd1',
            status: tripStatus,
            currency: 'USD',
            paymentMode: 'card',
          };
    const prisma = {
      trip: { findUnique: jest.fn().mockResolvedValue(trip) },
      user: { findUnique: jest.fn().mockResolvedValue({ email: 'r@x.com' }) },
    };
    const payments = {
      captureForTrip: jest
        .fn()
        .mockResolvedValue({ fareFinal: 50, platformFee: 10, driverPayout: 40 }),
    };
    const realtime = { emitToUser: jest.fn() };
    const notifications = { notify: jest.fn().mockResolvedValue(undefined) };
    const email = { sendReceipt: jest.fn().mockResolvedValue(undefined) };
    const stateMachine = { transition: jest.fn().mockResolvedValue(undefined) };
    const metrics = { paymentFailed: jest.fn() };
    const processor = new PaymentsProcessor(
      payments as never,
      prisma as never,
      realtime as never,
      notifications as never,
      email as never,
      stateMachine as never,
      metrics as never,
    );
    return {
      processor,
      prisma,
      payments,
      realtime,
      notifications,
      email,
      stateMachine,
      metrics,
    };
  }

  const job = (attemptsMade: number, attempts = 6) =>
    ({ data: { tripId: 't1' }, attemptsMade, opts: { attempts } }) as unknown as Job<{
      tripId: string;
    }>;

  it('captures and emits the real split to rider and driver, then sends the receipt', async () => {
    const { processor, payments, realtime, email } = build();
    await processor.process(job(0));
    expect(payments.captureForTrip).toHaveBeenCalledWith('t1');
    const settled = expect.objectContaining({
      tripId: 't1',
      fareFinal: 50,
      platformFee: 10,
      driverPayout: 40,
      paymentStatus: 'captured',
    });
    expect(realtime.emitToUser).toHaveBeenCalledWith('r1', 'trip:payment_settled', settled);
    expect(realtime.emitToUser).toHaveBeenCalledWith('d1', 'trip:payment_settled', settled);
    expect(email.sendReceipt).toHaveBeenCalledWith('r@x.com', 't1', 50, 'USD');
  });

  it('rethrows a failed capture so BullMQ retries, without flagging the trip early', async () => {
    const { processor, payments, stateMachine, realtime } = build();
    payments.captureForTrip.mockRejectedValue(new Error('gateway timeout'));
    await expect(processor.process(job(0))).rejects.toThrow('gateway timeout');
    expect(stateMachine.transition).not.toHaveBeenCalled();
    expect(realtime.emitToUser).not.toHaveBeenCalled();
  });

  it('flips the trip to payment_failed and tells both parties on the last attempt', async () => {
    const { processor, payments, stateMachine, realtime, notifications } = build();
    payments.captureForTrip.mockRejectedValue(new Error('card declined'));
    await expect(processor.process(job(5, 6))).rejects.toThrow('card declined');
    expect(stateMachine.transition).toHaveBeenCalledWith(
      expect.objectContaining({
        tripId: 't1',
        from: TripStatus.completed,
        to: TripStatus.payment_failed,
      }),
    );
    expect(realtime.emitToUser).toHaveBeenCalledWith('r1', 'trip:payment_failed', { tripId: 't1' });
    expect(realtime.emitToUser).toHaveBeenCalledWith('d1', 'trip:payment_failed', { tripId: 't1' });
    expect(notifications.notify).toHaveBeenCalledWith(
      'r1',
      expect.objectContaining({ data: expect.objectContaining({ kind: 'payment_failed' }) }),
    );
  });

  it('is a no-op for a trip that is no longer completed (or missing)', async () => {
    const a = build(TripStatus.payment_failed);
    await a.processor.process(job(0));
    expect(a.payments.captureForTrip).not.toHaveBeenCalled();
    const b = build(null);
    await b.processor.process(job(0));
    expect(b.payments.captureForTrip).not.toHaveBeenCalled();
  });
});
