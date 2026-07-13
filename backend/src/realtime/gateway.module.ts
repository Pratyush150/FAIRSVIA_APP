import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { RealtimeGateway } from './realtime.gateway';
import { LocationModule } from '../location/location.module';
import { DispatchModule } from '../dispatch/dispatch.module';
import { TripsModule } from '../trips/trips.module';
import { DriversModule } from '../drivers/drivers.module';

/// Hosts the Socket.IO gateway and wires it to the feature services. Kept
/// separate from RealtimeModule (the global RealtimeService) to avoid cycles.
@Module({
  imports: [
    JwtModule.register({}),
    LocationModule,
    DispatchModule,
    TripsModule,
    DriversModule,
  ],
  providers: [RealtimeGateway],
})
export class GatewayModule {}
