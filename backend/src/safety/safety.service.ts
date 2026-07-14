import {
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';

interface SosInput {
  lat?: number;
  lng?: number;
}

/**
 * Safety toolkit. An SOS during a trip is recorded as an auditable trip_event
 * (so ops can review it and it survives) and logged at WARN. Returns a shareable
 * trip summary the rider can send to a trusted contact.
 */
@Injectable()
export class SafetyService {
  private readonly logger = new Logger('Safety');

  constructor(private readonly prisma: PrismaService) {}

  async raiseSos(userId: string, tripId: string, input: SosInput) {
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) throw new NotFoundException('Trip not found');
    const role =
      userId === trip.riderId
        ? 'rider'
        : userId === trip.driverId
          ? 'driver'
          : null;
    if (!role) throw new ForbiddenException('Not a participant of this trip');

    await this.prisma.tripEvent.create({
      data: {
        tripId,
        fromStatus: trip.status,
        toStatus: trip.status, // SOS doesn't change trip state; audit only.
        actor: role,
        meta: {
          event: 'sos',
          lat: input.lat ?? null,
          lng: input.lng ?? null,
          at: new Date().toISOString(),
        },
      },
    });

    this.logger.warn(
      `SOS raised by ${role} ${userId} on trip ${tripId} ` +
        `@ ${input.lat ?? '?'},${input.lng ?? '?'} (status ${trip.status})`,
    );

    return {
      ok: true,
      tripId,
      status: trip.status,
      summary: {
        tripId,
        status: trip.status,
        pickup: trip.pickupAddr,
        dropoff: trip.dropoffAddr,
        raisedBy: role,
      },
    };
  }

  /** Recent SOS alerts for the admin safety view. */
  async recentSos(limit = 50) {
    const events = await this.prisma.tripEvent.findMany({
      where: { meta: { path: ['event'], equals: 'sos' } },
      orderBy: { createdAt: 'desc' },
      take: Math.min(limit, 200),
    });
    return events.map((e) => ({
      tripId: e.tripId,
      actor: e.actor,
      at: e.createdAt,
      meta: e.meta,
    }));
  }
}
