import { Logger } from '@nestjs/common';
import type Redis from 'ioredis';
import type { ThrottlerStorage } from '@nestjs/throttler';
import type { ThrottlerStorageRecord } from '@nestjs/throttler/dist/throttler-storage-record.interface';

/**
 * Redis-backed counter store for @nestjs/throttler so limits hold across
 * replicas (the library default is per-process memory). One Lua round-trip per
 * request: bump the fixed-window counter, and once it overflows, set a block
 * key for `blockDuration`. Fails open on a Redis error — the app is unusable
 * without Redis anyway, and a limiter outage must not take the API down.
 */
const SCRIPT = `
local blockTtl = redis.call('PTTL', KEYS[2])
if blockTtl > 0 then
  local hits = tonumber(redis.call('GET', KEYS[1]) or '0')
  local ttl = redis.call('PTTL', KEYS[1])
  return {hits, ttl, 1, blockTtl}
end
local hits = redis.call('INCR', KEYS[1])
if hits == 1 then redis.call('PEXPIRE', KEYS[1], ARGV[1]) end
local ttl = redis.call('PTTL', KEYS[1])
if hits > tonumber(ARGV[2]) then
  redis.call('SET', KEYS[2], '1', 'PX', ARGV[3])
  return {hits, ttl, 1, tonumber(ARGV[3])}
end
return {hits, ttl, 0, 0}
`;

export class RedisThrottlerStorage implements ThrottlerStorage {
  private readonly logger = new Logger('Throttle');

  constructor(private readonly client: Pick<Redis, 'eval'>) {}

  async increment(
    key: string,
    ttl: number,
    limit: number,
    blockDuration: number,
    throttlerName: string,
  ): Promise<ThrottlerStorageRecord> {
    const hitsKey = `throttle:${throttlerName}:${key}`;
    const blockKey = `${hitsKey}:block`;
    try {
      const [hits, ttlMs, blocked, blockMs] = (await this.client.eval(
        SCRIPT,
        2,
        hitsKey,
        blockKey,
        String(ttl),
        String(limit),
        String(blockDuration),
      )) as [number, number, number, number];
      const toSeconds = (ms: number, fallback: number) =>
        Math.ceil((ms > 0 ? ms : fallback) / 1000);
      return {
        totalHits: hits,
        timeToExpire: toSeconds(ttlMs, ttl),
        isBlocked: blocked === 1,
        timeToBlockExpire: blocked === 1 ? toSeconds(blockMs, blockDuration) : 0,
      };
    } catch (e) {
      this.logger.warn(`rate-limit store unavailable, failing open: ${e}`);
      return { totalHits: 0, timeToExpire: 0, isBlocked: false, timeToBlockExpire: 0 };
    }
  }
}
