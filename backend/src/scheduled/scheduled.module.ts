import { BullModule } from '@nestjs/bullmq';
import { Global, Module } from '@nestjs/common';
import { QUEUE_SCHEDULED } from '../common/queue/queue.constants';
import { DispatchModule } from '../dispatch/dispatch.module';
import { ScheduledService } from './scheduled.service';
import { ScheduledProcessor } from './scheduled.processor';

@Global()
@Module({
  imports: [
    BullModule.registerQueue({ name: QUEUE_SCHEDULED }),
    DispatchModule,
  ],
  providers: [ScheduledService, ScheduledProcessor],
  exports: [ScheduledService],
})
export class ScheduledModule {}
