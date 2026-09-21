import { Global, Logger, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { GEO_PROVIDER, GeoProvider as GeoProviderLike } from './geo-provider.interface';
import { GoogleGeoProvider } from './google-geo.provider';
import { OsmGeoProvider } from './osm-geo.provider';
import { StubGeoProvider } from './stub-geo.provider';
import { FallbackGeoProvider } from './fallback-geo.provider';
import { InstrumentedGeoProvider } from './instrumented-geo.provider';
import { MetricsService } from '../common/metrics/metrics.service';
import { PlacesController } from './places.controller';

@Global()
@Module({
  controllers: [PlacesController],
  providers: [
    {
      // Provider precedence: Google (if key) > self-hosted OSM (OSRM +
      // Nominatim, if both URLs set) > deterministic stub (no config needed).
      provide: GEO_PROVIDER,
      useFactory: (config: ConfigService, metrics: MetricsService) => {
        // Every provider is wrapped so its calls land in
        // vendor_request_duration_seconds. Wrapping happens per-provider, not
        // around the composed fallback, so Google and OSM are measured
        // separately — which is what makes a quota wall visible (google errors
        // climbing while osm takes over) instead of averaged away.
        const instrument = (p: GeoProviderLike, vendor: string) =>
          new InstrumentedGeoProvider(p, vendor, metrics);
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
          const google = instrument(new GoogleGeoProvider(key), 'google');
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
              instrument(
                new OsmGeoProvider(osrm as string, nominatim as string),
                'osm',
              ),
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
          return instrument(
            new OsmGeoProvider(osrm as string, nominatim as string),
            'osm',
          );
        }
        return instrument(new StubGeoProvider(), 'stub');
      },
      inject: [ConfigService, MetricsService],
    },
  ],
  exports: [GEO_PROVIDER],
})
export class GeoModule {}
