import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';

@Injectable()
export class FavoritesService {
  constructor(private readonly prisma: PrismaService) {}

  /** Add a driver to the rider's favourites (idempotent). The target must be
   *  an existing driver — a random/unknown id is a 404, not a dangling row. */
  async add(riderId: string, driverId: string) {
    const target = await this.prisma.user.findUnique({
      where: { id: driverId },
      select: { id: true, driverProfile: { select: { userId: true } } },
    });
    if (!target || !target.driverProfile) {
      throw new NotFoundException('Driver not found');
    }
    await this.prisma.favoriteDriver.upsert({
      where: { riderId_driverId: { riderId, driverId } },
      create: { riderId, driverId },
      update: {},
    });
    return { favorited: true, driverId };
  }

  /** Remove a driver from the rider's favourites (idempotent). */
  async remove(riderId: string, driverId: string) {
    await this.prisma.favoriteDriver.deleteMany({
      where: { riderId, driverId },
    });
    return { favorited: false, driverId };
  }

  /** The rider's favourite drivers with basic profile info, newest first. */
  async list(riderId: string) {
    const favorites = await this.prisma.favoriteDriver.findMany({
      where: { riderId },
      orderBy: { createdAt: 'desc' },
    });
    if (favorites.length === 0) return [];
    const drivers = await this.prisma.user.findMany({
      where: { id: { in: favorites.map((f) => f.driverId) } },
      select: {
        id: true,
        fullName: true,
        ratingAvg: true,
        driverProfile: {
          select: { vehicleModel: true, plateNumber: true },
        },
      },
    });
    const byId = new Map(drivers.map((d) => [d.id, d]));
    return favorites.map((f) => {
      const d = byId.get(f.driverId);
      return {
        driverId: f.driverId,
        name: d?.fullName ?? null,
        vehicleModel: d?.driverProfile?.vehicleModel ?? null,
        plateNumber: d?.driverProfile?.plateNumber ?? null,
        ratingAvg: d?.ratingAvg ? Number(d.ratingAvg) : null,
        since: f.createdAt,
      };
    });
  }

  /** Just the driver ids a rider has favourited (used by dispatch ordering). */
  async favoriteDriverIds(riderId: string): Promise<Set<string>> {
    const rows = await this.prisma.favoriteDriver.findMany({
      where: { riderId },
      select: { driverId: true },
    });
    return new Set(rows.map((r) => r.driverId));
  }
}
