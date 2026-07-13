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
@Global()
@Module({
  imports: [
    BullModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const url = config.get<string>('redisUrl') ?? 'redis://localhost:6379';
        const parsed = new URL(url);
        return {
          connection: {
            host: parsed.hostname,
            port: Number(parsed.port || 6379),
            // BullMQ requires this to be null for its blocking commands.
            maxRetriesPerRequest: null,
          },
        };
      },
    }),
  ],
  exports: [BullModule],
})
export class QueueModule {}
