import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { TripStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { CreateRatingDto } from './dto/create-rating.dto';

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

@Injectable()
export class RatingsService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Two-way rating: either party rates the other after a completed trip.
   * One rating per (trip, rater) — re-submitting updates it. The ratee's
   * running average is recomputed incrementally so we never scan history.
   */
  async rateTrip(fromUser: string, tripId: string, dto: CreateRatingDto) {
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) throw new NotFoundException('Trip not found');

    const isRider = trip.riderId === fromUser;
    const isDriver = trip.driverId === fromUser;
    if (!isRider && !isDriver) {
      throw new ForbiddenException('Not your trip');
    }
    if (trip.status !== TripStatus.completed) {
      throw new BadRequestException('Can only rate a completed trip');
    }
    const toUser = isRider ? trip.driverId : trip.riderId;
    if (!toUser) {
      throw new BadRequestException('No counterparty to rate');
    }

    return this.prisma.$transaction(async (tx) => {
      const existing = await tx.rating.findUnique({
        where: { tripId_fromUser: { tripId, fromUser } },
      });

      const rating = await tx.rating.upsert({
        where: { tripId_fromUser: { tripId, fromUser } },
        create: {
          tripId,
          fromUser,
          toUser,
          stars: dto.stars,
          comment: dto.comment,
          tags: dto.tags ?? [],
        },
        update: {
          stars: dto.stars,
          comment: dto.comment,
          tags: dto.tags ?? [],
        },
      });

      // Recompute the ratee's average incrementally.
      const ratee = await tx.user.findUnique({ where: { id: toUser } });
      if (ratee) {
        const count = ratee.ratingCount;
        const avg = Number(ratee.ratingAvg);
        let newCount: number;
        let newAvg: number;
        if (existing) {
          // Replace the old star value; count is unchanged.
          newCount = count;
          const total = avg * count - existing.stars + dto.stars;
          newAvg = count > 0 ? round2(total / count) : dto.stars;
        } else {
          newCount = count + 1;
          const total = avg * count + dto.stars;
          newAvg = round2(total / newCount);
        }
        await tx.user.update({
          where: { id: toUser },
          data: { ratingAvg: newAvg, ratingCount: newCount },
        });
      }

      return {
        id: rating.id,
        tripId,
        toUser,
        stars: rating.stars,
        comment: rating.comment,
        tags: rating.tags,
      };
    });
  }

  /** The rating this user gave for a trip (or null). */
  async getMyRating(userId: string, tripId: string) {
    const rating = await this.prisma.rating.findUnique({
      where: { tripId_fromUser: { tripId, fromUser: userId } },
    });
    return rating
      ? {
          id: rating.id,
          stars: rating.stars,
          comment: rating.comment,
          tags: rating.tags,
        }
      : null;
  }
}
