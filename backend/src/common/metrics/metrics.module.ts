import { Global, Module } from '@nestjs/common';
import { APP_INTERCEPTOR } from '@nestjs/core';
import { BullModule } from '@nestjs/bullmq';
import { MetricsService } from './metrics.service';
import { MetricsInterceptor } from './metrics.interceptor';
import { MetricsController } from './metrics.controller';
import { BusinessMetricsService } from './business-metrics.service';
import { QUEUE_DISPATCH, QUEUE_NOTIFICATIONS } from '../queue/queue.constants';

/** Prometheus metrics: a /metrics endpoint + a global request interceptor. */
@Global()
@Module({
  imports: [
    BullModule.registerQueue(
      { name: QUEUE_DISPATCH },
      { name: QUEUE_NOTIFICATIONS },
    ),
  ],
  controllers: [MetricsController],
  providers: [
    MetricsService,
    BusinessMetricsService,
    { provide: APP_INTERCEPTOR, useClass: MetricsInterceptor },
  ],
  exports: [MetricsService],
})
export class MetricsModule {}
