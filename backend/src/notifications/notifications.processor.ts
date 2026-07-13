import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Job } from 'bullmq';
import { NotificationsService } from './notifications.service';
import { PushMessage } from './push-provider.interface';
import { QUEUE_NOTIFICATIONS } from '../common/queue/queue.constants';

/** Delivers queued push notifications, with BullMQ retrying failed sends. */
@Processor(QUEUE_NOTIFICATIONS, { concurrency: 10 })
export class NotificationsProcessor extends WorkerHost {
  constructor(private readonly notifications: NotificationsService) {
    super();
  }

  async process(
    job: Job<{ userId: string; message: PushMessage }>,
  ): Promise<void> {
    await this.notifications.deliver(job.data.userId, job.data.message);
  }

  onModuleDestroy(): Promise<void> {
    return this.worker?.close() ?? Promise.resolve();
  }
}
