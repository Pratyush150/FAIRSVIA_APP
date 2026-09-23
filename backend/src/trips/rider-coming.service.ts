import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { TripStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { RealtimeService } from '../realtime/realtime.service';

/** Repeat taps inside this window do not ping the driver again. */
export const RIDER_COMING_DEBOUNCE_S = 60;

/**
 * "I'm on my way": the rider tells the driver waiting (or arriving) at the
 * pickup that they are coming out, so the driver does not give up or call.
 */
@Injectable()
export class RiderComingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly realtime: RealtimeService,
  ) {}

  async notify(riderId: string, tripId: string) {
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) throw new NotFoundException('Trip not found');
    if (trip.riderId !== riderId) throw new ForbiddenException('Not your trip');
    if (
      !trip.driverId ||
      (trip.status !== TripStatus.accepted && trip.status !== TripStatus.arrived)
    ) {
      throw new BadRequestException('Your driver is not waiting for you right now.');
    }

    const at = new Date();
    const first = await this.redis.client.set(
      `trip:${tripId}:rider_coming`,
      at.toISOString(),
      'EX',
      RIDER_COMING_DEBOUNCE_S,
      'NX',
    );
    if (first) {
      this.realtime.emitToUser(trip.driverId, 'trip:rider_coming', {
        tripId,
        at: at.toISOString(),
      });
      await this.prisma.tripEvent.create({
        data: {
          tripId,
          fromStatus: trip.status,
          toStatus: trip.status,
          actor: 'rider',
          meta: { event: 'rider_coming', at: at.toISOString() },
        },
      });
    }
    return { ok: true, driverNotified: first === 'OK' };
  }
}
