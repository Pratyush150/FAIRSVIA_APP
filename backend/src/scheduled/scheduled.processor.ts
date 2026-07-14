import { Logger } from '@nestjs/common';
import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Job } from 'bullmq';
import { QUEUE_SCHEDULED } from '../common/queue/queue.constants';
import { ScheduledService } from './scheduled.service';

/**
 * Fires a delayed job at each scheduled ride's time to promote it to a live
 * request. Idempotent — a cancelled/already-promoted trip is a no-op — so a
 * retry after a crash is safe.
 */
@Processor(QUEUE_SCHEDULED, { concurrency: 20 })
export class ScheduledProcessor extends WorkerHost {
  private readonly logger = new Logger('ScheduledProcessor');

  constructor(private readonly scheduled: ScheduledService) {
    super();
  }

  async process(job: Job<{ tripId: string }>): Promise<void> {
    await this.scheduled.promote(job.data.tripId);
  }

  onModuleDestroy(): Promise<void> {
    return this.worker?.close() ?? Promise.resolve();
  }
}
