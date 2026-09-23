import { Logger } from '@nestjs/common';
import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Job } from 'bullmq';
import { DispatchService } from './dispatch.service';
import { QUEUE_DISPATCH } from '../common/queue/queue.constants';
import { drainAndClose } from '../common/queue/drain';

/**
 * Runs the dispatch offer-loop as a durable job. If this process dies mid-match,
 * BullMQ re-runs the job (the trip is still MATCHING, so runDispatch resumes).
 *
 * Concurrency is high because a dispatch job is almost entirely I/O-wait (it
 * holds its slot while polling Redis for the offered driver's reply), not CPU.
 * A small pool serializes under a burst of simultaneous ride requests; load
 * testing showed 20 backing up at ~60 concurrent, so we run a wide pool.
 */
@Processor(QUEUE_DISPATCH, { concurrency: 100 })
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
    return drainAndClose(this.worker);
  }
}
