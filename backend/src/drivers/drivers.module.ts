import { Module } from '@nestjs/common';
import { DriversService } from './drivers.service';
import { DriversController } from './drivers.controller';
import { DemandMapService } from './demand-map.service';

@Module({
  controllers: [DriversController],
  providers: [DriversService, DemandMapService],
  exports: [DriversService],
})
export class DriversModule {}
