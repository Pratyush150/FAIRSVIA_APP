import {
  BadRequestException,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { RideTier, TripStatus, UserRole } from '@prisma/client';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { RealtimeService } from '../realtime/realtime.service';
import { OnboardingDto } from './dto/onboarding.dto';
import { TIER_KEYS } from '../pricing/fare-config';

/** Why the server (not the driver) took a driver offline. */
export type ForcedOfflineReason =
  | 'disconnect' // socket dropped / closed without an explicit offline
  | 'stale_location' // no GPS ping for PRESENCE_STALE_MS while "online"
  | 'presence_lost' // reconnect found no live presence for a DB-online driver
  | 'deactivated'; // admin deactivated the account

@Injectable()
export class DriversService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly config: ConfigService,
    private readonly realtime: RealtimeService,
  ) {}

  /** Create/refresh the driver profile and mark the user as a driver. Documents
   *  are auto-approved when DRIVER_AUTO_VERIFY is on (dev default); otherwise the
   *  driver onboards as pending and an admin must verify before they go online. */
  async onboarding(userId: string, dto: OnboardingDto) {
    const autoVerify = this.config.get<boolean>('driverAutoVerify') ?? true;
    // Re-verification: a verified driver who changes an identity/vehicle
    // document field (plate, licence) goes back to pending — the approval was
    // for the old documents. DRIVER_AUTO_VERIFY (dev-only) keeps auto-approving.
    const existing = await this.prisma.driverProfile.findUnique({
      where: { userId },
      select: { docsVerified: true, plateNumber: true, licenseNo: true },
    });
    const identityChanged =
      !!existing &&
      (existing.plateNumber !== dto.plateNumber ||
        (existing.licenseNo ?? null) !== (dto.licenseNo ?? null));
    const resetVerification = !autoVerify && !!existing?.docsVerified && identityChanged;
    const profile = await this.prisma.driverProfile.upsert({
      where: { userId },
      create: {
        userId,
        vehicleMake: dto.vehicleMake,
        vehicleModel: dto.vehicleModel,
        vehicleColor: dto.vehicleColor,
        plateNumber: dto.plateNumber,
        vehicleTier: dto.vehicleTier as RideTier,
        licenseNo: dto.licenseNo,
        docsVerified: autoVerify,
      },
      update: {
        vehicleMake: dto.vehicleMake,
        vehicleModel: dto.vehicleModel,
        vehicleColor: dto.vehicleColor,
        plateNumber: dto.plateNumber,
        vehicleTier: dto.vehicleTier as RideTier,
        licenseNo: dto.licenseNo,
        ...(resetVerification ? { docsVerified: false } : {}),
      },
    });
    await this.prisma.user.update({
      where: { id: userId },
      data: { role: UserRole.driver },
    });
    return profile;
  }

  async getProfile(userId: string) {
    const profile = await this.prisma.driverProfile.findUnique({
      where: { userId },
    });
    if (!profile) throw new BadRequestException('Complete onboarding first');
    return profile;
  }

  async setStatus(userId: string, status: 'online' | 'offline') {
    const profile = await this.getProfile(userId);

    if (status === 'online') {
      if (!profile.docsVerified) {
        throw new ForbiddenException('Documents are not verified yet');
      }
      await this.redis.client.set(RedisKeys.driverStatus(userId), 'online');
      await this.redis.client.set(
        RedisKeys.driverTier(userId),
        profile.vehicleTier,
      );
    } else {
      // Don't let a driver drop offline mid-trip — goOffline wipes the
      // active-trip Redis linkage, which stops rider location streaming and trip
      // metering. Make them finish the ride first.
      const activeTrip = await this.redis.client.get(
        RedisKeys.driverActiveTrip(userId),
      );
      if (activeTrip) {
        throw new BadRequestException(
          'Finish your current trip before going offline.',
        );
      }
      await this.goOffline(userId, profile.vehicleTier);
    }

    await this.prisma.driverProfile.update({
      where: { userId },
      data: { status },
    });
    return { status };
  }

  /**
   * Server-initiated offline (socket drop, stale GPS, ...). Unlike the
   * driver's own request this (a) never fires mid-trip — a brief drop must
   * let the driver reconnect and resume, (b) keeps the durable profile status
   * in step with Redis (the API audit found `driver_profiles.status` stuck at
   * 'online' after a disconnect), and (c) tells the driver app why, via
   * `driver:status_changed`, so its UI can't keep showing "Online" while the
   * server has stopped offering it trips. Returns whether it flipped.
   */
  async forceOffline(
    userId: string,
    tier: string | null,
    reason: ForcedOfflineReason,
  ): Promise<boolean> {
    const onTrip = await this.redis.client.get(RedisKeys.driverActiveTrip(userId));
    if (onTrip) return false;
    const resolvedTier =
      tier ?? (await this.redis.client.get(RedisKeys.driverTier(userId)));
    await this.goOffline(userId, resolvedTier ?? 'economy');
    if (!tier && !resolvedTier) {
      // Unknown tier: sweep every pool so no GEO entry can linger.
      for (const t of TIER_KEYS) {
        await this.redis.client.zrem(RedisKeys.driversGeo(t), userId);
      }
    }
    await this.prisma.driverProfile
      .updateMany({ where: { userId, status: 'online' }, data: { status: 'offline' } })
      .catch(() => undefined);
    this.realtime.emitToUser(userId, 'driver:status_changed', {
      status: 'offline',
      reason,
    });
    return true;
  }

  /** Remove the driver from the live pool and clear ephemeral state. */
  async goOffline(userId: string, tier: string) {
    await this.redis.client.set(RedisKeys.driverStatus(userId), 'offline');
    await this.redis.client.zrem(RedisKeys.driversGeo(tier), userId);
    await this.redis.client.del(
      RedisKeys.driverLoc(userId),
      RedisKeys.driverActiveTrip(userId),
      RedisKeys.driverActiveRider(userId),
      RedisKeys.driverTier(userId),
    );
  }

  async earnings(userId: string, range: 'today' | 'week') {
    const since = new Date();
    if (range === 'today') {
      since.setHours(0, 0, 0, 0);
    } else {
      since.setDate(since.getDate() - 7);
    }
    const trips = await this.prisma.trip.findMany({
      where: {
        driverId: userId,
        status: TripStatus.completed,
        completedAt: { gte: since },
      },
    });
    const total = trips.reduce(
      (sum, t) => sum + Number(t.fareFinal ?? t.fareEstimate ?? 0),
      0,
    );
    return {
      range,
      total: Math.round(total * 100) / 100,
      trips: trips.length,
    };
  }
}
