import { Module } from '@nestjs/common';
import { SurgeModule } from '../surge/surge.module';
import { ComparisonService } from './comparison.service';
import { ComparisonController } from './comparison.controller';
import { CalibrationService } from './calibration.service';

/**
 * Price-comparison domain. PricingService (our fare) and GEO_PROVIDER (routing)
 * are global; SurgeModule is imported for the live multiplier. CalibrationService
 * keeps the competitor rate cards fitted to real samples. Exports
 * ComparisonService so TripsService can enrich its estimate response with the
 * same comparison block.
 */
@Module({
  imports: [SurgeModule],
  controllers: [ComparisonController],
  providers: [ComparisonService, CalibrationService],
  exports: [ComparisonService],
})
export class ComparisonModule {}
