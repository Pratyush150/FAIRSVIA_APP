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
import { OnboardingDto } from './dto/onboarding.dto';

@Injectable()
export class DriversService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly config: ConfigService,
  ) {}

  /** Create/refresh the driver profile and mark the user as a driver. Documents
   *  are auto-approved when DRIVER_AUTO_VERIFY is on (dev default); otherwise the
   *  driver onboards as pending and an admin must verify before they go online. */
  async onboarding(userId: string, dto: OnboardingDto) {
    const autoVerify = this.config.get<boolean>('driverAutoVerify') ?? true;
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
