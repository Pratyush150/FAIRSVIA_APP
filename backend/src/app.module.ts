import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import configuration from './common/config/configuration';
import { PrismaModule } from './common/prisma/prisma.module';
import { RedisModule } from './common/redis/redis.module';
import { QueueModule } from './common/queue/queue.module';
import { LoggingModule } from './common/logging/logging.module';
import { MetricsModule } from './common/metrics/metrics.module';
import { AuthModule } from './auth/auth.module';
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
import { HealthController } from './health/health.controller';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [configuration],
    }),
    LoggingModule, // structured pino logging
    MetricsModule, // Prometheus /metrics + request interceptor
    PrismaModule,
    RedisModule,
    QueueModule, // global BullMQ connection
    RealtimeModule, // global RealtimeService
    TripStateModule, // global TripStateMachine
    NotificationsModule, // global NotificationsService
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
  ],
  controllers: [HealthController],
})
export class AppModule {}
