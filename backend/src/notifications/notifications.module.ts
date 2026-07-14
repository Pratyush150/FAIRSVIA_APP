import { Global, Logger, Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { ConfigService } from '@nestjs/config';
import { NotificationsService } from './notifications.service';
import { NotificationsController } from './notifications.controller';
import { InboxController } from './inbox.controller';
import { NotificationsProcessor } from './notifications.processor';
import { PUSH_PROVIDER } from './push-provider.interface';
import { MockPushProvider } from './mock-push.provider';
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
        const key = config.get<string>('fcmServerKey');
        if (key && key.length > 0) {
          // A real FCM/APNs provider would be constructed here; until then the
          // mock keeps the pipeline exercised.
          Logger.warn(
            'FCM_SERVER_KEY set but no real provider wired yet; using mock.',
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
