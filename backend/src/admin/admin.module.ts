import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { AdminService } from './admin.service';
import { AdminController } from './admin.controller';
import {
  QUEUE_DISPATCH,
  QUEUE_NOTIFICATIONS,
} from '../common/queue/queue.constants';

@Module({
  imports: [
    BullModule.registerQueue({ name: QUEUE_DISPATCH }),
    BullModule.registerQueue({ name: QUEUE_NOTIFICATIONS }),
  ],
  controllers: [AdminController],
  providers: [AdminService],
})
export class AdminModule {}
