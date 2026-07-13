import { Global, Logger, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { GEO_PROVIDER } from './geo-provider.interface';
import { GoogleGeoProvider } from './google-geo.provider';
import { StubGeoProvider } from './stub-geo.provider';
import { PlacesController } from './places.controller';

@Global()
@Module({
  controllers: [PlacesController],
  providers: [
    {
      // Real Google provider when a key is configured; deterministic stub otherwise.
      provide: GEO_PROVIDER,
      useFactory: (config: ConfigService) => {
        const key = config.get<string>('googleMapsApiKey');
        if (key && key.length > 0) {
          Logger.log('Using Google Maps geo provider', 'GeoModule');
          return new GoogleGeoProvider(key);
        }
        return new StubGeoProvider();
      },
      inject: [ConfigService],
    },
  ],
  exports: [GEO_PROVIDER],
})
export class GeoModule {}
