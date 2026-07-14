import { Module } from '@nestjs/common';
import { SurgeService } from './surge.service';
import { SurgeController } from './surge.controller';

/// Demand/supply surge engine. Uses the global Redis provider; exports
/// SurgeService so pricing/trips can apply the live multiplier.
@Module({
  controllers: [SurgeController],
  providers: [SurgeService],
  exports: [SurgeService],
})
export class SurgeModule {}
