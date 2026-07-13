import { Injectable, NotFoundException } from '@nestjs/common';
import { TripStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';

/** Trip statuses that count as "in flight" right now. */
const ACTIVE_STATUSES: TripStatus[] = [
  TripStatus.requested,
  TripStatus.matching,
  TripStatus.accepted,
  TripStatus.arrived,
  TripStatus.in_progress,
];

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  /** Headline counters for the dashboard. */
  async stats() {
    const [users, drivers, activeTrips, completedTrips, byStatus] =
      await Promise.all([
        this.prisma.user.count(),
        this.prisma.driverProfile.count(),
        this.prisma.trip.count({ where: { status: { in: ACTIVE_STATUSES } } }),
        this.prisma.trip.count({ where: { status: TripStatus.completed } }),
        this.prisma.trip.groupBy({ by: ['status'], _count: { _all: true } }),
      ]);

    const online = await this.countOnlineDrivers();
    const tripsByStatus: Record<string, number> = {};
    for (const row of byStatus) {
      tripsByStatus[row.status] = row._count._all;
    }

    // Gross revenue = captured ride payments (excludes cancellations/tips split).
    const revenue = await this.prisma.payment.aggregate({
      where: { status: 'captured', kind: 'ride' },
      _sum: { amount: true, platformFee: true },
    });

    return {
      users,
      drivers,
      onlineDrivers: online,
      activeTrips,
      completedTrips,
      tripsByStatus,
      grossRevenue: Number(revenue._sum.amount ?? 0),
      platformRevenue: Number(revenue._sum.platformFee ?? 0),
    };
  }

  /** Recent trips (optionally filtered by status), newest first. */
  async trips(params: { status?: string; limit?: number }) {
    const limit = Math.min(params.limit ?? 50, 200);
    const where =
      params.status === 'active'
        ? { status: { in: ACTIVE_STATUSES } }
        : params.status
          ? { status: params.status as TripStatus }
          : {};

    const trips = await this.prisma.trip.findMany({
      where,
      orderBy: { requestedAt: 'desc' },
      take: limit,
      include: {
        rider: { select: { id: true, fullName: true, phone: true } },
        driver: { select: { id: true, fullName: true, phone: true } },
      },
    });

    return trips.map((t) => ({
      id: t.id,
      status: t.status,
      tier: t.tier,
      rider: t.rider
        ? { id: t.rider.id, name: t.rider.fullName, phone: t.rider.phone }
        : null,
      driver: t.driver
        ? { id: t.driver.id, name: t.driver.fullName, phone: t.driver.phone }
        : null,
      pickup: t.pickupAddr,
      dropoff: t.dropoffAddr,
      fare: Number(t.fareFinal ?? t.fareEstimate ?? 0),
      currency: t.currency,
      requestedAt: t.requestedAt,
      completedAt: t.completedAt,
    }));
  }

  /** Users list with a simple phone/name search. */
  async users(params: { q?: string; limit?: number }) {
    const limit = Math.min(params.limit ?? 50, 200);
    const q = params.q?.trim();
    const users = await this.prisma.user.findMany({
      where: q
        ? {
            OR: [
              { phone: { contains: q } },
              { fullName: { contains: q, mode: 'insensitive' } },
            ],
          }
        : {},
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
    return users.map((u) => ({
      id: u.id,
      phone: u.phone,
      name: u.fullName,
      role: u.role,
      ratingAvg: Number(u.ratingAvg),
      ratingCount: u.ratingCount,
      isActive: u.isActive,
      createdAt: u.createdAt,
    }));
  }

  /** Drivers with their durable profile + live online status from Redis. */
  async drivers(params: { limit?: number }) {
    const limit = Math.min(params.limit ?? 50, 200);
    const profiles = await this.prisma.driverProfile.findMany({
      take: limit,
      include: {
        user: { select: { id: true, fullName: true, phone: true, isActive: true, ratingAvg: true } },
      },
    });

    return Promise.all(
      profiles.map(async (p) => {
        const status =
          (await this.redis.get(RedisKeys.driverStatus(p.userId))) ?? 'offline';
        return {
          id: p.userId,
          name: p.user.fullName,
          phone: p.user.phone,
          isActive: p.user.isActive,
          rating: Number(p.user.ratingAvg),
          vehicle: {
            make: p.vehicleMake,
            model: p.vehicleModel,
            color: p.vehicleColor,
            plate: p.plateNumber,
            tier: p.vehicleTier,
          },
          totalTrips: p.totalTrips,
          liveStatus: status,
        };
      }),
    );
  }

  /** Activate or deactivate a user account. */
  async setActive(userId: string, isActive: boolean) {
    const user = await this.prisma.user
      .update({ where: { id: userId }, data: { isActive } })
      .catch(() => null);
    if (!user) throw new NotFoundException('User not found');
    return { id: user.id, isActive: user.isActive };
  }

  private async countOnlineDrivers(): Promise<number> {
    // Small scale (~10k users): a scan over driver status keys is fine. At
    // larger scale, maintain an "online" set instead.
    const keys = await this.redis.client.keys('driver:*:status');
    if (keys.length === 0) return 0;
    const values = await this.redis.client.mget(keys);
    return values.filter((v) => v && v !== 'offline').length;
  }
}
