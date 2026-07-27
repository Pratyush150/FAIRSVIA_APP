import { Module } from '@nestjs/common';
import { SurgeModule } from '../surge/surge.module';
import { ComparisonService } from './comparison.service';
import { ComparisonController } from './comparison.controller';

/**
 * Price-comparison domain. PricingService (our fare) and GEO_PROVIDER (routing)
 * are global; SurgeModule is imported for the live multiplier. Exports
 * ComparisonService so TripsService can enrich its estimate response with the
 * same comparison block.
 */
@Module({
  imports: [SurgeModule],
  controllers: [ComparisonController],
  providers: [ComparisonService],
  exports: [ComparisonService],
})
export class ComparisonModule {}
