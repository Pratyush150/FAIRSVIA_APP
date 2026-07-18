import { Global, Logger, Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { ConfigService } from '@nestjs/config';
import { NotificationsService } from './notifications.service';
import { NotificationsController } from './notifications.controller';
import { InboxController } from './inbox.controller';
import { NotificationsProcessor } from './notifications.processor';
import { PUSH_PROVIDER } from './push-provider.interface';
import { MockPushProvider } from './mock-push.provider';
import { FcmPushProvider } from './fcm-push.provider';
import { QUEUE_NOTIFICATIONS } from '../common/queue/queue.constants';

@Global()
@Module({
  imports: [BullModule.registerQueue({ name: QUEUE_NOTIFICATIONS })],
  controllers: [NotificationsController, InboxController],
  providers: [
    NotificationsService,
    NotificationsProcessor,
    {
      provide: PUSH_PROVIDER,
      useFactory: (config: ConfigService) => {
        // Real FCM (HTTP v1) when a service-account JSON is configured; else the
        // mock keeps the pipeline exercised. The legacy FCM_SERVER_KEY API was
        // shut down in 2024, so a bare server key can no longer send.
        const saJson = config.get<string>('fcmServiceAccountJson') ?? '';
        if (saJson.length > 0) {
          const account = FcmPushProvider.parse(saJson);
          if (account) return new FcmPushProvider(account);
          Logger.warn(
            'FCM_SERVICE_ACCOUNT_JSON set but could not be parsed; using mock.',
            'NotificationsModule',
          );
        } else if ((config.get<string>('fcmServerKey') ?? '').length > 0) {
          Logger.warn(
            'FCM_SERVER_KEY is set but the legacy API is discontinued — set ' +
              'FCM_SERVICE_ACCOUNT_JSON for real push; using mock for now.',
            'NotificationsModule',
          );
        }
        return new MockPushProvider();
      },
      inject: [ConfigService],
    },
  ],
  exports: [NotificationsService],
})
export class NotificationsModule {}
