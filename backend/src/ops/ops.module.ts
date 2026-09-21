import { Global, Module } from '@nestjs/common';
import { OpsFlagsService } from './ops-flags.service';
import { OpsController } from './ops.controller';

/**
 * Runtime kill switches. Global because the enforcement points are spread
 * across geo, dispatch, surge and payments, and each one only needs to ask
 * "is this flag on".
 */
@Global()
@Module({
  controllers: [OpsController],
  providers: [OpsFlagsService],
  exports: [OpsFlagsService],
})
export class OpsModule {}
