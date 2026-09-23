import { Module } from '@nestjs/common';
import { APP_FILTER } from '@nestjs/core';
import { ConfigModule } from '@nestjs/config';
import { SentryModule } from '@sentry/nestjs/setup';
import { SentryGlobalFilter } from '@sentry/nestjs/setup';
import configuration from './common/config/configuration';
import { PrismaModule } from './common/prisma/prisma.module';
import { RedisModule } from './common/redis/redis.module';
import { QueueModule } from './common/queue/queue.module';
import { LoggingModule } from './common/logging/logging.module';
import { MetricsModule } from './common/metrics/metrics.module';
import { ThrottleModule } from './common/throttle/throttle.module';
import { AuthModule } from './auth/auth.module';
import { SmsModule } from './common/sms/sms.module';
import { UsersModule } from './users/users.module';
import { GeoModule } from './geo/geo.module';
import { PricingModule } from './pricing/pricing.module';
import { TripStateModule } from './trips/trip-state.module';
import { TripsModule } from './trips/trips.module';
import { DriversModule } from './drivers/drivers.module';
import { LocationModule } from './location/location.module';
import { DispatchModule } from './dispatch/dispatch.module';
import { PaymentsModule } from './payments/payments.module';
import { RatingsModule } from './ratings/ratings.module';
import { NotificationsModule } from './notifications/notifications.module';
import { AdminModule } from './admin/admin.module';
import { RealtimeModule } from './realtime/realtime.module';
import { GatewayModule } from './realtime/gateway.module';
import { ChatModule } from './chat/chat.module';
import { SafetyModule } from './safety/safety.module';
import { SurgeModule } from './surge/surge.module';
import { ComparisonModule } from './comparison/comparison.module';
import { PromoModule } from './promo/promo.module';
import { ScheduledModule } from './scheduled/scheduled.module';
import { LedgerModule } from './ledger/ledger.module';
import { FavoritesModule } from './favorites/favorites.module';
import { SupportModule } from './support/support.module';
import { BackgroundModule } from './background/background.module';
import { EmailModule } from './email/email.module';
import { AuditModule } from './common/audit/audit.module';
import { OpsModule } from './ops/ops.module';
import { HealthController } from './health/health.controller';

@Module({
  imports: [
    SentryModule.forRoot(), // must be the first import — wires the request/error interceptors
    ConfigModule.forRoot({
      isGlobal: true,
      load: [configuration],
    }),
    LoggingModule, // structured pino logging
    MetricsModule, // Prometheus /metrics + request interceptor
    AuditModule, // append-only log of every admin write
    OpsModule, // runtime kill switches (geo/dispatch/surge/payouts)
    PrismaModule,
    RedisModule,
    ThrottleModule, // global per-IP rate limiting (Redis-backed)
    QueueModule, // global BullMQ connection
    RealtimeModule, // global RealtimeService
    TripStateModule, // global TripStateMachine
    NotificationsModule, // global NotificationsService
    EmailModule, // global EmailService (SES / mock)
    SmsModule, // global SMS gateway (login OTPs + passenger messages)
    AuthModule,
    UsersModule,
    GeoModule,
    PricingModule,
    DriversModule,
    LocationModule,
    DispatchModule,
    TripsModule,
    PaymentsModule,
    RatingsModule,
    AdminModule,
    GatewayModule,
    ChatModule,
    SafetyModule,
    SurgeModule,
    ComparisonModule,
    PromoModule,
    ScheduledModule,
    LedgerModule,
    FavoritesModule,
    SupportModule,
    BackgroundModule,
  ],
  controllers: [HealthController],
  providers: [
    // Uncaught exceptions reach Sentry before Nest's default handling. A no-op
    // when SENTRY_DSN is unset (see instrument.ts).
    { provide: APP_FILTER, useClass: SentryGlobalFilter },
  ],
})
export class AppModule {}
