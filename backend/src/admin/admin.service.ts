import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { TripStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { MetricsService } from '../common/metrics/metrics.service';
import {
  QUEUE_DISPATCH,
  QUEUE_NOTIFICATIONS,
} from '../common/queue/queue.constants';

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
    private readonly metrics: MetricsService,
    @InjectQueue(QUEUE_DISPATCH) private readonly dispatchQueue: Queue,
    @InjectQueue(QUEUE_NOTIFICATIONS) private readonly notificationsQueue: Queue,
  ) {}

  /**
   * Operational snapshot for the monitoring dashboard: HTTP throughput, queue
   * health, the trip funnel, live drivers, and process/system stats.
   */
  async opsMetrics() {
    const [dispatchCounts, notifyCounts, byStatus, activeTrips, online] =
      await Promise.all([
        this.dispatchQueue.getJobCounts(
          'waiting',
          'active',
          'completed',
          'failed',
          'delayed',
        ),
        this.notificationsQueue.getJobCounts(
          'waiting',
          'active',
          'completed',
          'failed',
          'delayed',
        ),
        this.prisma.trip.groupBy({ by: ['status'], _count: { _all: true } }),
        this.prisma.trip.count({ where: { status: { in: ACTIVE_STATUSES } } }),
        this.countOnlineDrivers(),
      ]);

    const tripFunnel: Record<string, number> = {};
    for (const row of byStatus) tripFunnel[row.status] = row._count._all;

    const mem = process.memoryUsage();
    return {
      generatedAt: new Date().toISOString(),
      system: {
        uptimeSec: Math.floor(process.uptime()),
        rssMb: Math.round(mem.rss / 1e6),
        heapUsedMb: Math.round(mem.heapUsed / 1e6),
        nodeVersion: process.version,
      },
      http: this.metrics.snapshot(),
      queues: {
        dispatch: dispatchCounts,
        notifications: notifyCounts,
      },
      tripFunnel,
      onlineDrivers: online,
      activeTrips,
    };
  }

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
  async drivers(params: { limit?: number; pending?: boolean }) {
    const limit = Math.min(params.limit ?? 50, 200);
    const profiles = await this.prisma.driverProfile.findMany({
      take: limit,
      where: params.pending ? { docsVerified: false } : undefined,
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
          docsVerified: p.docsVerified,
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

  /** Approve or reject a driver's documents (KYC gate). A driver cannot go
   *  online until verified. */
  async verifyDriver(userId: string, docsVerified: boolean) {
    const profile = await this.prisma.driverProfile
      .update({ where: { userId }, data: { docsVerified } })
      .catch(() => null);
    if (!profile) throw new NotFoundException('Driver profile not found');
    return { id: userId, docsVerified: profile.docsVerified };
  }

  /**
   * Live operational snapshot for the admin map: every online driver's current
   * position (from Redis GEO, per tier) and every in-flight trip's endpoints.
   */
  async live() {
    const drivers: {
      driverId: string;
      lat: number;
      lng: number;
      heading: number;
      tier: string | null;
      status: string;
    }[] = [];

    // Enumerate every online driver (idle OR on a trip) from their status keys,
    // then read each one's last-known position. We use the per-driver location
    // hash rather than the geo pool, because busy drivers are removed from the
    // pool when matched but should still appear on the ops map.
    const statusKeys = await this.redis.client.keys('driver:*:status');
    const statuses = statusKeys.length
      ? await this.redis.client.mget(...statusKeys)
      : [];
    for (let i = 0; i < statusKeys.length; i++) {
      const status = statuses[i];
      if (!status || status === 'offline') continue;
      // key shape: driver:{id}:status
      const driverId = statusKeys[i].split(':')[1];
      const loc = await this.redis.client.hgetall(RedisKeys.driverLoc(driverId));
      if (!loc?.lat || !loc?.lng) continue;
      const tier = await this.redis.client.get(RedisKeys.driverTier(driverId));
      drivers.push({
        driverId,
        lat: Number(loc.lat),
        lng: Number(loc.lng),
        heading: Number(loc.heading ?? 0),
        tier,
        status,
      });
    }

    const active = await this.prisma.trip.findMany({
      where: { status: { in: ACTIVE_STATUSES } },
      orderBy: { requestedAt: 'desc' },
      take: 200,
      select: {
        id: true,
        status: true,
        driverId: true,
        pickupLat: true,
        pickupLng: true,
        dropoffLat: true,
        dropoffLng: true,
        pickupAddr: true,
        dropoffAddr: true,
      },
    });

    return {
      drivers,
      trips: active.map((t) => ({
        id: t.id,
        status: t.status,
        driverId: t.driverId,
        pickup: { lat: t.pickupLat, lng: t.pickupLng, address: t.pickupAddr },
        dropoff: {
          lat: t.dropoffLat,
          lng: t.dropoffLng,
          address: t.dropoffAddr,
        },
      })),
    };
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
