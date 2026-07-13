import { Global, Module } from '@nestjs/common';
import { RealtimeService } from './realtime.service';

/// Global provider for room-targeted emits. Kept separate from the gateway so
/// feature services can inject it without a circular dependency on the gateway.
@Global()
@Module({
  providers: [RealtimeService],
  exports: [RealtimeService],
})
export class RealtimeModule {}
