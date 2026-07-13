import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { DispatchService } from './dispatch.service';
import { DispatchProcessor } from './dispatch.processor';
import { QUEUE_DISPATCH } from '../common/queue/queue.constants';

@Module({
  imports: [BullModule.registerQueue({ name: QUEUE_DISPATCH })],
  providers: [DispatchService, DispatchProcessor],
  exports: [DispatchService],
})
export class DispatchModule {}
