import { Global, Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { ConfigService } from '@nestjs/config';

/**
 * Wires BullMQ to the same Redis the rest of the app uses. Feature modules add
 * their own queues with `BullModule.registerQueue({ name })` and process them
 * with `@Processor(name)`.
 *
 * Putting durable work (dispatch offer-loop, push sends) on a queue means it
 * survives a backend restart: an in-flight job is retried/resumed instead of
 * lost, and it can be processed by any replica (multi-node safe).
 */
/**
 * BullMQ connection options from a redis:// URL. Credentials and db index
 * must be carried over: the production Redis requires a password
 * (docker-compose.prod `--requirepass`), and dropping it made every queue
 * fail NOAUTH.
 */
export function bullConnectionFromUrl(url: string) {
  const parsed = new URL(url);
  const db = Number(parsed.pathname.replace('/', '') || 0);
  return {
    host: parsed.hostname,
    port: Number(parsed.port || 6379),
    username: parsed.username ? decodeURIComponent(parsed.username) : undefined,
    password: parsed.password ? decodeURIComponent(parsed.password) : undefined,
    db: Number.isFinite(db) ? db : 0,
    // BullMQ requires this to be null for its blocking commands.
    maxRetriesPerRequest: null,
  };
}

@Global()
@Module({
  imports: [
    BullModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const url = config.get<string>('redisUrl') ?? 'redis://localhost:6379';
        return {
          // Namespaced so a test run never consumes (or is slowed by) the
          // jobs of a dev server sharing the same Redis. Default = BullMQ's.
          prefix: process.env.QUEUE_PREFIX || 'bull',
          connection: bullConnectionFromUrl(url),
        };
      },
    }),
  ],
  exports: [BullModule],
})
export class QueueModule {}
