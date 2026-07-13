import { Logger } from '@nestjs/common';
import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Job } from 'bullmq';
import { DispatchService } from './dispatch.service';
import { QUEUE_DISPATCH } from '../common/queue/queue.constants';

/**
 * Runs the dispatch offer-loop as a durable job. If this process dies mid-match,
 * BullMQ re-runs the job (the trip is still MATCHING, so runDispatch resumes).
 * `concurrency` lets several trips be matched at once.
 */
@Processor(QUEUE_DISPATCH, { concurrency: 20 })
export class DispatchProcessor extends WorkerHost {
  private readonly logger = new Logger('DispatchProcessor');

  constructor(private readonly dispatch: DispatchService) {
    super();
  }

  async process(job: Job<{ tripId: string }>): Promise<void> {
    const { tripId } = job.data;
    await this.dispatch.runDispatch(tripId);
  }

  onModuleDestroy(): Promise<void> {
    // WorkerHost registers a worker; close it cleanly on shutdown.
    return this.worker?.close() ?? Promise.resolve();
  }
}
