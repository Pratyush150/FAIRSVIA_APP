import { Module } from '@nestjs/common';
import { DriversService } from './drivers.service';
import { DriversController } from './drivers.controller';
import { DemandMapService } from './demand-map.service';
import { FatigueService } from './fatigue/fatigue.service';
import { FatigueSweeper } from './fatigue/fatigue.sweeper';
import { FatigueController } from './fatigue/fatigue.controller';
import { DestinationModeService } from './destination/destination-mode.service';
import { DestinationModeController } from './destination/destination-mode.controller';

@Module({
  controllers: [DriversController, FatigueController, DestinationModeController],
  providers: [DriversService, DemandMapService, FatigueService, FatigueSweeper, DestinationModeService],
  exports: [DriversService, FatigueService, DestinationModeService],
})
export class DriversModule {}
