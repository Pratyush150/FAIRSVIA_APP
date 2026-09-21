import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerModule } from '@nestjs/throttler';
import { RedisService } from '../redis/redis.service';
import { AppThrottlerGuard } from './app-throttler.guard';
import { RedisThrottlerStorage } from './redis-throttler.storage';
import { bucketFor, throttleConfig } from './throttle.config';

/**
 * Registers the three named throttlers (see throttle.config.ts) and installs
 * the guard globally. `tight` / `moderate` only count requests whose route
 * matches their allow-list; `default` counts everything.
 */
@Module({
  imports: [
    ThrottlerModule.forRootAsync({
      inject: [RedisService],
      useFactory: (redis: RedisService) => {
        const cfg = throttleConfig();
        return {
          storage: new RedisThrottlerStorage(redis.client),
          errorMessage: 'Too many requests. Slow down and try again shortly.',
          throttlers: [
            { name: 'default', ttl: cfg.ttlMs, limit: cfg.defaultLimit },
            {
              name: 'tight',
              ttl: cfg.ttlMs,
              limit: cfg.tightLimit,
              skipIf: (ctx) => bucketFor(ctx) !== 'tight',
            },
            {
              name: 'moderate',
              ttl: cfg.ttlMs,
              limit: cfg.moderateLimit,
              skipIf: (ctx) => bucketFor(ctx) !== 'moderate',
            },
          ],
        };
      },
    }),
  ],
  providers: [{ provide: APP_GUARD, useClass: AppThrottlerGuard }],
})
export class ThrottleModule {}
