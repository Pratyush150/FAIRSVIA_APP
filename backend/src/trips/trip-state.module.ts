import { Global, Module } from '@nestjs/common';
import { TripStateMachine } from './trip-state-machine';

/// Global so both TripsModule and DispatchModule can inject the state machine
/// without importing each other (avoids a circular module dependency).
@Global()
@Module({
  providers: [TripStateMachine],
  exports: [TripStateMachine],
})
export class TripStateModule {}
