import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { businessDayKey } from '../time/business-day';

/**
 * Records that a user was active today, for DAU / MAU.
 *
 * Called on every authenticated request, so it must cost almost nothing on
 * the hot path: an in-process map answers "already recorded today" for free;
 * only the first sighting per process per day touches Redis, and only the
 * first sighting across ALL processes (Redis SET NX) writes to Postgres.
 * Never throws and never delays the caller.
 */
@Injectable()
export class ActivityService {
  private readonly logger = new Logger(ActivityService.name);
  private readonly tz: string;
  private day = '';
  private readonly seen = new Set<string>();

  constructor(
    config: ConfigService,
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {
    this.tz = config.get<string>('businessTimezone') ?? 'Asia/Tashkent';
  }

  touch(userId: string, now: Date = new Date()): void {
    const day = businessDayKey(now, this.tz);
    if (day !== this.day) {
      this.day = day;
      this.seen.clear();
    }
    if (this.seen.has(userId)) return;
    this.seen.add(userId);
    void this.record(userId, day).catch((e) => {
      // Let a later request retry rather than losing the day.
      this.seen.delete(userId);
      this.logger.warn(`activity not recorded for ${userId}: ${String(e)}`);
    });
  }

  private async record(userId: string, day: string): Promise<void> {
    const first = await this.redis.client.set(`active:${day}:${userId}`, '1', 'EX', 2 * 86400, 'NX');
    if (first !== 'OK') return;
    try {
      await this.prisma.$executeRaw`
        INSERT INTO user_active_days (user_id, day)
        VALUES (${userId}::uuid, ${day}::date)
        ON CONFLICT DO NOTHING`;
    } catch (e) {
      await this.redis.client.del(`active:${day}:${userId}`).catch(() => undefined);
      throw e;
    }
  }
}
