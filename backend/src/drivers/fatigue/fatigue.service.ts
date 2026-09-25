import { ConflictException, Injectable, Logger } from '@nestjs/common';
import { RedisService } from '../../common/redis/redis.service';
import { RedisKeys } from '../../common/redis/redis.keys';
import { FatigueRaw, FatigueState, FatigueKeys, fatigueState } from './fatigue.rules';

/**
 * Fatigue limit bookkeeping (rule in limits.rules.ts). State lives in Redis
 * next to the online-time keys; the open session is the same
 * `driver:{id}:onlineSince` the earnings page uses.
 */
@Injectable()
export class FatigueService {
  private readonly logger = new Logger('Fatigue');

  constructor(private readonly redis: RedisService) {}

  async raw(userId: string): Promise<FatigueRaw & { warned: boolean; remindSince: number; remindN: number }> {
    const [h, since] = await Promise.all([
      this.redis.client.hgetall(FatigueKeys.fatigue(userId)),
      this.redis.client.get(RedisKeys.driverOnlineSince(userId)),
    ]);
    return {
      acc: Number(h?.acc) || 0,
      lastOff: Number(h?.lastOff) || null,
      onlineSince: Number(since) || null,
      warned: h?.warned === '1',
      remindSince: Number(h?.remindSince) || 0,
      remindN: Number(h?.remindN) || 0,
    };
  }

  async state(userId: string, now = Date.now()): Promise<FatigueState> {
    return fatigueState(await this.raw(userId), now);
  }

  /**
   * Called before a driver goes online. Refuses (409 DRIVER_REST_REQUIRED)
   * while the required break is not done; otherwise zeroes the counter if
   * the driver has just finished a full break, and starts tracking them.
   */
  async beforeOnline(userId: string, now = Date.now()): Promise<void> {
    const raw = await this.raw(userId);
    const s = fatigueState(raw, now);
    if (s.overLimit) {
      const mins = Math.ceil(s.restSecondsLeft / 60);
      const h = Math.floor(mins / 60);
      const m = mins % 60;
      throw new ConflictException({
        code: 'DRIVER_REST_REQUIRED',
        message: `You've reached ${Math.round(s.limitSeconds / 360) / 10} h online. Rest for ${[h > 0 ? `${h} h` : '', m > 0 || h === 0 ? `${m} min` : ''].filter(Boolean).join(' ')} before going online again.`,
        restSecondsLeft: s.restSecondsLeft,
        restUntil: s.restUntil,
        onlineSeconds: s.onlineSeconds,
        limitSeconds: s.limitSeconds,
      });
    }
    if (!raw.onlineSince && s.onlineSeconds === 0 && raw.acc > 0) {
      // A full break was taken: start a fresh count.
      await this.redis.client.hset(FatigueKeys.fatigue(userId), { acc: 0, warned: 0 });
    }
    await this.redis.client.sadd(FatigueKeys.fatigueTracked(), userId);
  }

  /** Called as the driver goes offline, BEFORE the online session key is
   *  cleared: credits the session to the counter. Best-effort. */
  async onOffline(userId: string, now = Date.now()): Promise<void> {
    try {
      const since = Number(await this.redis.client.get(RedisKeys.driverOnlineSince(userId)));
      await this.redis.client.srem(FatigueKeys.fatigueTracked(), userId);
      if (!since) return;
      const secs = Math.max(0, Math.round((now - since) / 1000));
      const key = FatigueKeys.fatigue(userId);
      await this.redis.client.hincrby(key, 'acc', secs);
      await this.redis.client.hset(key, { lastOff: now });
      await this.redis.client.expire(key, 3 * 86400);
    } catch (e) {
      this.logger.warn(`fatigue onOffline failed for ${userId}: ${e}`);
    }
  }

  /** Dispatch gate: false once the driver is at/over the limit. Fails open
   *  (a Redis hiccup must not starve the whole fleet of offers). */
  async canTakeOffers(userId: string, now = Date.now()): Promise<boolean> {
    try {
      return !(await this.state(userId, now)).overLimit;
    } catch {
      return true;
    }
  }

  async tracked(): Promise<string[]> {
    return this.redis.client.smembers(FatigueKeys.fatigueTracked());
  }

  async markWarned(userId: string): Promise<void> {
    await this.redis.client.hset(FatigueKeys.fatigue(userId), { warned: 1 });
  }

  async markReminded(userId: string, since: number, n: number): Promise<void> {
    await this.redis.client.hset(FatigueKeys.fatigue(userId), { remindSince: since, remindN: n });
  }
}
