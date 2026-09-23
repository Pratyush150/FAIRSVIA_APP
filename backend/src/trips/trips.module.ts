import { Module } from '@nestjs/common';
import { TripsService } from './trips.service';
import { TripsController } from './trips.controller';
import { DispatchModule } from '../dispatch/dispatch.module';
import { SurgeModule } from '../surge/surge.module';
import { ComparisonModule } from '../comparison/comparison.module';
import { RiderComingService } from './rider-coming.service';
import { TripStopsService } from './trip-stops.service';

@Module({
  imports: [DispatchModule, SurgeModule, ComparisonModule],
  controllers: [TripsController],
  providers: [TripsService, RiderComingService, TripStopsService],
  exports: [TripsService],
})
export class TripsModule {}
