import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, TripStatus } from '@prisma/client';
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

    const runTxn = () =>
      this.prisma.$transaction(
        async (tx) => {
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

          // Recompute the ratee's average from the authoritative Rating rows
          // (not an incremental read-modify-write on the user row), inside a
          // serializable transaction — so concurrent ratings can neither lose an
          // update nor drift the average via float accumulation.
          const agg = await tx.rating.aggregate({
            where: { toUser },
            _avg: { stars: true },
            _count: true,
          });
          await tx.user.update({
            where: { id: toUser },
            data: {
              ratingAvg: round2(Number(agg._avg.stars ?? dto.stars)),
              ratingCount: agg._count,
            },
          });

          return {
            id: rating.id,
            tripId,
            toUser,
            stars: rating.stars,
            comment: rating.comment,
            tags: rating.tags,
          };
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );

    // One retry on a serialization conflict (concurrent rating of the same user).
    try {
      return await runTxn();
    } catch (e) {
      if (
        e instanceof Prisma.PrismaClientKnownRequestError &&
        e.code === 'P2034'
      ) {
        return runTxn();
      }
      throw e;
    }
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
