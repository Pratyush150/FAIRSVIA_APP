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
import { startOfBusinessDay } from '../common/time/business-day';
import { CURRENCY } from '../pricing/fare-config';
import { PLATE_EXAMPLE, isValidPlate, normalizePlate } from './plates';

/** Why the server (not the driver) took a driver offline. */
export type ForcedOfflineReason =
  | 'disconnect' // socket dropped / closed without an explicit offline
  | 'stale_location' // no GPS ping for PRESENCE_STALE_MS while "online"
  | 'presence_lost' // reconnect found no live presence for a DB-online driver
  | 'deactivated' // admin deactivated the account
  | 'account_deleted'; // the driver deleted their own account

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
    // Riders are told to match the plate before getting in, so it must be the
    // real one, in the market's format — and stored in one form.
    const plate = normalizePlate(dto.plateNumber);
    if (!isValidPlate(plate, CURRENCY)) {
      const example = PLATE_EXAMPLE[CURRENCY];
      throw new BadRequestException({
        code: 'PLATE_INVALID',
        message: example
          ? `Enter the number plate as it is on the car, e.g. ${example}.`
          : 'Enter the number plate as it is on the car.',
      });
    }
    dto = { ...dto, plateNumber: plate };
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

  /**
   * The profile as the app should see it: `status` is the LIVE presence
   * (Redis, what dispatch actually consults), falling back to the stored row
   * when Redis has no entry. The stored column can lag behind a forced
   * offline, and a driver polling this must learn the truth.
   */
  async getProfileWithPresence(userId: string) {
    const profile = await this.getProfile(userId);
    let live: string | null = null;
    try {
      live = await this.redis.client.get(RedisKeys.driverStatus(userId));
    } catch {
      live = null;
    }
    return { ...profile, status: live ?? profile.status };
  }

  async setStatus(userId: string, status: 'online' | 'offline') {
    const profile = await this.getProfile(userId);

    if (status === 'online') {
      if (!profile.docsVerified) {
        throw new ForbiddenException('Documents are not verified yet');
      }
      // Riders see the driver's name on the arriving screen and are told to
      // check it: a nameless "Driver" can't be verified, so no name, no rides.
      const user = await this.prisma.user.findUnique({
        where: { id: userId },
        select: { fullName: true },
      });
      if ((user?.fullName?.trim().length ?? 0) < 2) {
        throw new BadRequestException({
          code: 'NAME_REQUIRED',
          message: 'Add your full name in Account before going online — riders check it when you arrive.',
        });
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

  /**
   * What the driver actually earned: their share of each fare (`driverPayout`,
   * i.e. after the platform fee — tips are added into it by addTip, so it
   * already includes them), plus cancellation compensation.
   * Not the fare itself — the fare includes the platform's cut, and a
   * "today's earnings" that shows money the driver never gets is a promise
   * the payout will break.
   *
   * "Today" starts at midnight in the business time zone (Tashkent), not the
   * server's, which runs in UTC.
   */
  async earnings(userId: string, range: 'today' | 'week') {
    const tz = this.config.get<string>('businessTimezone') ?? 'Asia/Tashkent';
    const now = new Date();
    const since =
      range === 'today'
        ? startOfBusinessDay(now, tz)
        : new Date(now.getTime() - 7 * 86400_000);
    const settled = { in: ['captured', 'collected'] };
    const [rides, cancellations] = await Promise.all([
      this.prisma.trip.findMany({
        where: {
          driverId: userId,
          status: TripStatus.completed,
          completedAt: { gte: since },
        },
        select: { payment: { select: { status: true, driverPayout: true } } },
      }),
      this.prisma.payment.findMany({
        where: {
          kind: 'cancellation',
          status: settled,
          updatedAt: { gte: since },
          trip: { driverId: userId },
        },
        select: { driverPayout: true },
      }),
    ]);
    let total = 0;
    for (const { payment } of rides) {
      if (!payment || !settled.in.includes(payment.status)) continue;
      total += Number(payment.driverPayout ?? 0);
    }
    for (const c of cancellations) total += Number(c.driverPayout ?? 0);
    return {
      range,
      total: Math.round(total * 100) / 100,
      trips: rides.length,
    };
  }

}
