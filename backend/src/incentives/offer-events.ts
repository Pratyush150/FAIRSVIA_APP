import { PrismaService } from '../common/prisma/prisma.service';

/**
 * What happened to one offer (or one accepted trip) for a driver. The live
 * offer only ever exists in Redis; these rows are the durable record the
 * acceptance and cancellation rates are computed from.
 */
export type OfferOutcome =
  | 'accepted'
  | 'declined'
  | 'expired'
  | 'cancelled' // the driver cancelled an accepted trip
  | 'cancelled_no_show'; // ...because the rider never came — not held against them

/**
 * Append an outcome. Best-effort by design: a stats write must never fail a
 * dispatch or a cancel, so errors are swallowed (and the caller need not await).
 */
export async function recordOfferEvent(
  prisma: PrismaService,
  driverId: string,
  tripId: string,
  outcome: OfferOutcome,
): Promise<void> {
  try {
    await prisma.driverOfferEvent.create({ data: { driverId, tripId, outcome } });
  } catch {
    /* stats are advisory; never break the ride flow */
  }
}
