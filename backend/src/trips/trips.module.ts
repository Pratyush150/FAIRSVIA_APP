import { Module } from '@nestjs/common';
import { TripsService } from './trips.service';
import { TripsController } from './trips.controller';
import { DispatchModule } from '../dispatch/dispatch.module';
import { SurgeModule } from '../surge/surge.module';

@Module({
  imports: [DispatchModule, SurgeModule],
  controllers: [TripsController],
  providers: [TripsService],
  exports: [TripsService],
})
export class TripsModule {}
