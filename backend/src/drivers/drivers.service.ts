import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Optional,
} from '@nestjs/common';
import { RideTier, TripStatus, UserRole } from '@prisma/client';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { RealtimeService } from '../realtime/realtime.service';
import { OnboardingDto } from './dto/onboarding.dto';
import { TIER_KEYS } from '../pricing/fare-config';
import {
  businessDayKey,
  startOfBusinessDay,
} from '../common/time/business-day';
import { splitByBusinessDay } from './online-time';
import { FatigueService } from './fatigue/fatigue.service';

/** How long the per-day online-seconds hash outlives its last write. */
const ONLINE_SECS_TTL = 9 * 86400;
/** The earnings page lists at most this many trips. */
const EARNINGS_TRIP_LIMIT = 50;
import { CURRENCY } from '../pricing/fare-config';
import { PLATE_EXAMPLE, isValidPlate, normalizePlate } from './plates';

/** Why the server (not the driver) took a driver offline. */
export type ForcedOfflineReason =
  | 'disconnect' // socket dropped / closed without an explicit offline
  | 'stale_location' // no GPS ping for PRESENCE_STALE_MS while "online"
  | 'presence_lost' // reconnect found no live presence for a DB-online driver
  | 'deactivated' // admin deactivated the account
  | 'account_deleted' // the driver deleted their own account
  | 'fatigue'; // reached DRIVER_MAX_ONLINE_HOURS, must rest (fatigue/)

@Injectable()
export class DriversService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly config: ConfigService,
    private readonly realtime: RealtimeService,
    @Optional() private readonly fatigue?: FatigueService,
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
      // Fatigue limit: 409 DRIVER_REST_REQUIRED until the break is done.
      await this.fatigue?.beforeOnline(userId);
      await this.redis.client.set(RedisKeys.driverStatus(userId), 'online');
      await this.redis.client.set(
        RedisKeys.driverTier(userId),
        profile.vehicleTier,
      );
      await this.startOnlineSession(userId);
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
    await this.fatigue?.onOffline(userId); // before the session key is cleared
    await this.endOnlineSession(userId);
    await this.redis.client.set(RedisKeys.driverStatus(userId), 'offline');
    await this.redis.client.zrem(RedisKeys.driversGeo(tier), userId);
    await this.redis.client.del(
      RedisKeys.driverLoc(userId),
      RedisKeys.driverActiveTrip(userId),
      RedisKeys.driverActiveRider(userId),
      RedisKeys.driverTier(userId),
    );
  }

  private get tz(): string {
    return this.config.get<string>('businessTimezone') ?? 'Asia/Tashkent';
  }

  /** Mark the start of an online session (kept if one is already open —
   *  a repeated "online" must not reset the clock). Best-effort: online
   *  time is a display figure and must never block going online. */
  private async startOnlineSession(userId: string): Promise<void> {
    try {
      await this.redis.client.set(
        RedisKeys.driverOnlineSince(userId),
        String(Date.now()),
        'NX',
      );
    } catch {
      /* display-only */
    }
  }

  /** Close the open online session (if any) and credit its seconds to the
   *  business day(s) it spanned. Best-effort, like [startOnlineSession]. */
  private async endOnlineSession(userId: string): Promise<void> {
    try {
      const key = RedisKeys.driverOnlineSince(userId);
      const since = Number(await this.redis.client.get(key));
      if (!since) return;
      await this.redis.client.del(key);
      const parts = splitByBusinessDay(new Date(since), new Date(), this.tz);
      const hash = RedisKeys.driverOnlineSecs(userId);
      for (const [day, secs] of Object.entries(parts)) {
        if (secs > 0) await this.redis.client.hincrby(hash, day, secs);
      }
      await this.redis.client.expire(hash, ONLINE_SECS_TTL);
    } catch {
      /* display-only */
    }
  }

  /** Seconds online per business day, including the still-open session. */
  private async onlineSecondsByDay(userId: string): Promise<Record<string, number>> {
    try {
      const [stored, since] = await Promise.all([
        this.redis.client.hgetall(RedisKeys.driverOnlineSecs(userId)),
        this.redis.client.get(RedisKeys.driverOnlineSince(userId)),
      ]);
      const out: Record<string, number> = {};
      for (const [k, v] of Object.entries(stored ?? {})) out[k] = Number(v) || 0;
      if (since && Number(since) > 0) {
        const open = splitByBusinessDay(new Date(Number(since)), new Date(), this.tz);
        for (const [k, v] of Object.entries(open)) out[k] = (out[k] ?? 0) + v;
      }
      return out;
    } catch {
      return {};
    }
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
    const tz = this.tz;
    const now = new Date();
    const todayStart = startOfBusinessDay(now, tz);
    // The week is the last 7 business days (today + the 6 before), so the
    // total equals the sum of the daily bars the page draws.
    const weekStart = startOfBusinessDay(
      new Date(todayStart.getTime() - 6 * 86400_000 + 12 * 3600_000),
      tz,
    );
    const since = range === 'today' ? todayStart : weekStart;
    const settled = { in: ['captured', 'collected'] };
    const [rides, cancellations, online] = await Promise.all([
      this.prisma.trip.findMany({
        where: {
          driverId: userId,
          status: TripStatus.completed,
          completedAt: { gte: weekStart },
        },
        orderBy: { completedAt: 'desc' },
        select: {
          id: true,
          completedAt: true,
          pickupAddr: true,
          dropoffAddr: true,
          distanceM: true,
          tier: true,
          paymentMode: true,
          payment: {
            select: { status: true, driverPayout: true, tip: true },
          },
        },
      }),
      this.prisma.payment.findMany({
        where: {
          kind: 'cancellation',
          status: settled,
          updatedAt: { gte: weekStart },
          trip: { driverId: userId },
        },
        select: { driverPayout: true, updatedAt: true },
      }),
      this.onlineSecondsByDay(userId),
    ]);
    // Quest / incentive bonuses are real money in the driver's balance.
    const bonuses = await this.prisma.ledgerEntry.findMany({
      where: { driverId: userId, type: 'bonus', createdAt: { gte: weekStart } },
      select: { amount: true, createdAt: true },
    });

    // Seven daily buckets, oldest first.
    const days: { date: string; total: number; trips: number; onlineSeconds: number }[] = [];
    for (let i = 6; i >= 0; i--) {
      const at = new Date(todayStart.getTime() - i * 86400_000 + 12 * 3600_000);
      const date = businessDayKey(at, tz);
      days.push({ date, total: 0, trips: 0, onlineSeconds: online[date] ?? 0 });
    }
    const bucket = (at: Date) => days.find((d) => d.date === businessDayKey(at, tz));

    const earned = (p: { status: string; driverPayout: unknown } | null) =>
      p && settled.in.includes(p.status) ? Number(p.driverPayout ?? 0) : 0;

    let total = 0;
    let trips = 0;
    const list: {
      id: string;
      completedAt: Date | null;
      pickupAddr: string | null;
      dropoffAddr: string | null;
      distanceM: number | null;
      tier: string;
      paymentMode: string;
      earned: number;
      tip: number;
    }[] = [];
    for (const r of rides) {
      const amount = earned(r.payment);
      const b = r.completedAt ? bucket(r.completedAt) : undefined;
      if (b) {
        b.total += amount;
        b.trips += 1;
      }
      if (r.completedAt && r.completedAt >= since) {
        total += amount;
        trips += 1;
        if (list.length < EARNINGS_TRIP_LIMIT) {
          list.push({
            id: r.id,
            completedAt: r.completedAt,
            pickupAddr: r.pickupAddr,
            dropoffAddr: r.dropoffAddr,
            distanceM: r.distanceM,
            tier: r.tier,
            paymentMode: r.paymentMode,
            earned: round2(amount),
            tip: Number(r.payment?.tip ?? 0),
          });
        }
      }
    }
    let cancellationTotal = 0;
    for (const c of cancellations) {
      const amount = Number(c.driverPayout ?? 0);
      const b = bucket(c.updatedAt);
      if (b) b.total += amount;
      if (c.updatedAt >= since) {
        total += amount;
        cancellationTotal += amount;
      }
    }
    let bonusTotal = 0;
    for (const e of bonuses) {
      const amount = Number(e.amount);
      const b = bucket(e.createdAt);
      if (b) b.total += amount;
      if (e.createdAt >= since) {
        total += amount;
        bonusTotal += amount;
      }
    }
    for (const d of days) d.total = round2(d.total);

    const onlineSeconds =
      range === 'today'
        ? days[days.length - 1].onlineSeconds
        : days.reduce((a, d) => a + d.onlineSeconds, 0);

    return {
      range,
      total: round2(total),
      trips,
      onlineSeconds,
      cancellationFees: round2(cancellationTotal),
      bonuses: round2(bonusTotal),
      currency: CURRENCY,
      days,
      recentTrips: list,
    };
  }


}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
