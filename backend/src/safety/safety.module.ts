import { Module } from '@nestjs/common';
import { SafetyService } from './safety.service';
import { SafetyController } from './safety.controller';

/// Safety toolkit (SOS). Uses the global Prisma provider; records SOS alerts
/// to the trip audit log and exposes them to admins.
@Module({
  controllers: [SafetyController],
  providers: [SafetyService],
})
export class SafetyModule {}
