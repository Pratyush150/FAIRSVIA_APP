import { Global, Logger, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { GEO_PROVIDER } from './geo-provider.interface';
import { GoogleGeoProvider } from './google-geo.provider';
import { OsmGeoProvider } from './osm-geo.provider';
import { StubGeoProvider } from './stub-geo.provider';
import { PlacesController } from './places.controller';

@Global()
@Module({
  controllers: [PlacesController],
  providers: [
    {
      // Provider precedence: Google (if key) > self-hosted OSM (OSRM +
      // Nominatim, if both URLs set) > deterministic stub (no config needed).
      provide: GEO_PROVIDER,
      useFactory: (config: ConfigService) => {
        const key = config.get<string>('googleMapsApiKey');
        if (key && key.length > 0) {
          Logger.log('Using Google Maps geo provider', 'GeoModule');
          return new GoogleGeoProvider(key);
        }
        const osrm = config.get<string>('osrmBaseUrl');
        const nominatim = config.get<string>('nominatimBaseUrl');
        if (osrm && osrm.length > 0 && nominatim && nominatim.length > 0) {
          Logger.log('Using OpenStreetMap geo provider (OSRM + Nominatim)', 'GeoModule');
          return new OsmGeoProvider(osrm, nominatim);
        }
        return new StubGeoProvider();
      },
      inject: [ConfigService],
    },
  ],
  exports: [GEO_PROVIDER],
})
export class GeoModule {}
