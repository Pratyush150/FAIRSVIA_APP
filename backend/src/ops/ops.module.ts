import { Global, Module, forwardRef } from '@nestjs/common';
import { DispatchModule } from '../dispatch/dispatch.module';
import { OpsFlagsService } from './ops-flags.service';
import { OpsController } from './ops.controller';

/**
 * Runtime kill switches. Global because the enforcement points are spread
 * across geo, dispatch, surge and payments, and each one only needs to ask
 * "is this flag on".
 */
@Global()
@Module({
  // forwardRef: DispatchService depends on OpsFlagsService (to read the pause)
  // and this controller depends on DispatchService (to release what the pause
  // parked). The cycle is real and intentional; Nest needs to be told.
  imports: [forwardRef(() => DispatchModule)],
  controllers: [OpsController],
  providers: [OpsFlagsService],
  exports: [OpsFlagsService],
})
export class OpsModule {}
