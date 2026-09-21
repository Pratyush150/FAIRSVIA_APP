import { Global, Logger, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { GEO_PROVIDER } from './geo-provider.interface';
import { GoogleGeoProvider } from './google-geo.provider';
import { OsmGeoProvider } from './osm-geo.provider';
import { StubGeoProvider } from './stub-geo.provider';
import { FallbackGeoProvider } from './fallback-geo.provider';
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
        const osrm = config.get<string>('osrmBaseUrl');
        const nominatim = config.get<string>('nominatimBaseUrl');
        const hasOsm = !!(
          osrm &&
          osrm.length > 0 &&
          nominatim &&
          nominatim.length > 0
        );

        if (key && key.length > 0) {
          const google = new GoogleGeoProvider(key);
          // If self-hosted OSM is also configured, wrap Google with an OSRM/
          // Nominatim fallback so a Google outage, quota, or not-yet-enabled API
          // can never take geo down. Otherwise use Google alone.
          if (hasOsm) {
            Logger.log(
              'Using Google Maps geo provider (OSRM/Nominatim fallback)',
              'GeoModule',
            );
            return new FallbackGeoProvider(
              google,
              new OsmGeoProvider(osrm as string, nominatim as string),
            );
          }
          Logger.log('Using Google Maps geo provider', 'GeoModule');
          return google;
        }
        if (hasOsm) {
          Logger.log(
            'Using OpenStreetMap geo provider (OSRM + Nominatim)',
            'GeoModule',
          );
          return new OsmGeoProvider(osrm as string, nominatim as string);
        }
        return new StubGeoProvider();
      },
      inject: [ConfigService],
    },
  ],
  exports: [GEO_PROVIDER],
})
export class GeoModule {}
