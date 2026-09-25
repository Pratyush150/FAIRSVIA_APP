import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../common/prisma/prisma.service';
import { RedisService } from '../../common/redis/redis.service';
import { RedisKeys } from '../../common/redis/redis.keys';
import { RealtimeService } from '../../realtime/realtime.service';
import { businessDayKey } from '../../common/time/business-day';
import { haversineMeters } from '../../geo/geo.util';
import {
  DESTINATION_ARRIVED_RADIUS_M,
  DESTINATION_DEFAULT_USES_PER_DAY,
  DESTINATION_MAX_ACTIVE_MS,
  Point,
  autoOffReason,
  bringsCloser,
} from './destination.rules';
import { DestinationModeDto } from './destination.dto';

/** Redis keys owned by destination mode (hot, per driver; no Postgres). */
export const DestinationKeys = {
  // Active destination: hash {lat,lng,label,startedAt}. PEXPIRE'd at the 2 h
  // cap as a backstop for the explicit auto-off.
  active: (id: string) => `driver:${id}:dest`,
  // Activations used on a business day (Tashkent calendar), TTL'd 36 h.
  uses: (id: string, day: string) => `driver:${id}:destUses:${day}`,
  // The driver's saved "Home": hash {lat,lng,label}. No TTL.
  home: (id: string) => `driver:${id}:destHome`,
};

export interface ActiveDestination extends Point {
  label: string;
  startedAt: number;
}

export interface DestinationTrip {
  dropoffLat: number;
  dropoffLng: number;
}

@Injectable()
export class DestinationModeService {
  private readonly logger = new Logger('DestinationMode');

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly config: ConfigService,
    private readonly realtime: RealtimeService,
  ) {}

  get usesPerDay(): number {
    const raw = Number(this.config.get('DESTINATION_MODE_USES_PER_DAY'));
    return Number.isFinite(raw) && raw >= 0 ? Math.floor(raw) : DESTINATION_DEFAULT_USES_PER_DAY;
  }

  private get tz(): string {
    return this.config.get<string>('businessTimezone') ?? 'Asia/Tashkent';
  }

  private async requireDriver(userId: string) {
    const profile = await this.prisma.driverProfile.findUnique({ where: { userId } });
    if (!profile) throw new BadRequestException('Complete onboarding first');
  }

  private async usesToday(userId: string): Promise<number> {
    const day = businessDayKey(new Date(), this.tz);
    return Number((await this.redis.client.get(DestinationKeys.uses(userId, day))) ?? 0);
  }

  private async readActive(userId: string): Promise<ActiveDestination | null> {
    const h = await this.redis.client.hgetall(DestinationKeys.active(userId));
    if (!h || h.lat === undefined) return null;
    return {
      lat: Number(h.lat),
      lng: Number(h.lng),
      label: h.label ?? 'Destination',
      startedAt: Number(h.startedAt),
    };
  }

  private async readLoc(userId: string): Promise<Point | null> {
    const loc = await this.redis.client.hgetall(RedisKeys.driverLoc(userId));
    if (!loc || loc.lat === undefined) return null;
    return { lat: Number(loc.lat), lng: Number(loc.lng) };
  }

  /** Ends the mode and tells the app why (best-effort push). */
  async turnOff(userId: string, reason: 'arrived' | 'expired' | 'cancelled') {
    await this.redis.client.del(DestinationKeys.active(userId));
    if (reason !== 'cancelled') {
      try {
        this.realtime.emitToUser(userId, 'driver:destination_off', { reason });
      } catch {
        /* push is best-effort */
      }
    }
  }

  /** Current state, applying auto-off first so the app never shows a stale chip. */
  async get(userId: string) {
    await this.requireDriver(userId);
    let active = await this.readActive(userId);
    let endedReason: string | null = null;
    if (active) {
      const reason = autoOffReason(active.startedAt, Date.now(), await this.readLoc(userId), active);
      if (reason) {
        await this.turnOff(userId, reason);
        active = null;
        endedReason = reason;
      }
    }
    return this.view(userId, active, endedReason);
  }

  private async view(userId: string, active: ActiveDestination | null, endedReason: string | null = null) {
    const home = await this.redis.client.hgetall(DestinationKeys.home(userId));
    return {
      active: !!active,
      destination: active
        ? { lat: active.lat, lng: active.lng, label: active.label }
        : null,
      startedAt: active ? new Date(active.startedAt).toISOString() : null,
      expiresAt: active
        ? new Date(active.startedAt + DESTINATION_MAX_ACTIVE_MS).toISOString()
        : null,
      usesToday: await this.usesToday(userId),
      usesPerDay: this.usesPerDay,
      home:
        home && home.lat !== undefined
          ? { lat: Number(home.lat), lng: Number(home.lng), label: home.label ?? 'Home' }
          : null,
      endedReason,
    };
  }

  /**
   * Set (or move) the destination. Starting the mode uses one of today's
   * activations; changing the point while it is already on does not, and
   * keeps the original 2 h clock (so it can't be used to extend it).
   */
  async set(userId: string, dto: DestinationModeDto) {
    await this.requireDriver(userId);
    const label = (dto.label ?? '').trim() || 'Destination';
    const loc = await this.readLoc(userId);
    if (loc && haversineMeters(loc, dto) <= DESTINATION_ARRIVED_RADIUS_M) {
      throw new BadRequestException({
        message: 'You are already at that destination.',
        code: 'DESTINATION_TOO_CLOSE',
      });
    }
    if (dto.saveAsHome) {
      await this.redis.client.hset(DestinationKeys.home(userId), {
        lat: dto.lat,
        lng: dto.lng,
        label: dto.label?.trim() || 'Home',
      });
    }

    let existing = await this.readActive(userId);
    if (existing && autoOffReason(existing.startedAt, Date.now(), null, existing)) {
      await this.turnOff(userId, 'expired');
      existing = null;
    }
    let startedAt = existing?.startedAt ?? Date.now();
    if (!existing) {
      const day = businessDayKey(new Date(), this.tz);
      const key = DestinationKeys.uses(userId, day);
      const used = await this.redis.client.incr(key);
      await this.redis.client.expire(key, 36 * 3600);
      if (used > this.usesPerDay) {
        await this.redis.client.decr(key);
        throw new BadRequestException({
          message: `Destination mode can be used ${this.usesPerDay} times a day.`,
          code: 'DESTINATION_LIMIT_REACHED',
          usesPerDay: this.usesPerDay,
        });
      }
      startedAt = Date.now();
    }
    const key = DestinationKeys.active(userId);
    await this.redis.client.hset(key, { lat: dto.lat, lng: dto.lng, label, startedAt });
    await this.redis.client.pexpireat(key, startedAt + DESTINATION_MAX_ACTIVE_MS);
    return this.view(userId, { lat: dto.lat, lng: dto.lng, label, startedAt });
  }

  async clear(userId: string) {
    await this.requireDriver(userId);
    await this.turnOff(userId, 'cancelled');
    return this.view(userId, null);
  }

  /**
   * Dispatch filter: drops candidates in destination mode for whom this trip's
   * drop-off does not bring them meaningfully closer (see destination.rules).
   * Drivers not in the mode pass untouched. Applies auto-off on the way (a
   * driver who has arrived or run out of time is back to normal matching).
   * Fail-open: a Redis error never blocks matching.
   */
  async filterCandidates(trip: DestinationTrip, ids: string[]): Promise<string[]> {
    if (ids.length === 0) return ids;
    try {
      const pipe = this.redis.client.pipeline();
      for (const id of ids) pipe.hgetall(DestinationKeys.active(id));
      const res = await pipe.exec();
      const dropoff = { lat: trip.dropoffLat, lng: trip.dropoffLng };
      const out: string[] = [];
      for (let i = 0; i < ids.length; i++) {
        const id = ids[i];
        const h = res?.[i]?.[1] as Record<string, string> | null;
        if (!h || h.lat === undefined) {
          out.push(id);
          continue;
        }
        const dest = { lat: Number(h.lat), lng: Number(h.lng) };
        const loc = await this.readLoc(id);
        const reason = autoOffReason(Number(h.startedAt), Date.now(), loc, dest);
        if (reason) {
          await this.turnOff(id, reason);
          out.push(id);
          continue;
        }
        // No position yet: can't judge "closer" — don't offer (the driver
        // asked for filtered trips only).
        if (loc && bringsCloser(loc, dropoff, dest)) out.push(id);
      }
      return out;
    } catch (e) {
      this.logger.warn(`destination filter failed open: ${(e as Error).message}`);
      return ids;
    }
  }
}
