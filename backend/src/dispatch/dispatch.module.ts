import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { DispatchService } from './dispatch.service';
import { DispatchProcessor } from './dispatch.processor';
import { QUEUE_DISPATCH } from '../common/queue/queue.constants';
import { DriversModule } from '../drivers/drivers.module';
import { SurgeModule } from '../surge/surge.module';

@Module({
  imports: [
    BullModule.registerQueue({ name: QUEUE_DISPATCH }),
    DriversModule,
    SurgeModule,
  ],
  providers: [DispatchService, DispatchProcessor],
  exports: [DispatchService],
})
export class DispatchModule {}
