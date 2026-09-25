import { Global, Module } from '@nestjs/common';
import { DriverStatsService } from './driver-stats.service';
import { QuestsService } from './quests.service';
import { IncentivesController } from './incentives.controller';
import { QuestsAdminController } from './quests-admin.controller';

/**
 * Driver incentives: acceptance / cancellation rates and quests. Global so
 * trip completion can hand each finished trip to QuestsService.
 */
@Global()
@Module({
  controllers: [IncentivesController, QuestsAdminController],
  providers: [DriverStatsService, QuestsService],
  exports: [DriverStatsService, QuestsService],
})
export class IncentivesModule {}
