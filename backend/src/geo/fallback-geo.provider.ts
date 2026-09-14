import { Logger } from '@nestjs/common';
import {
  GeoProvider,
  LatLng,
  PlaceDetails,
  PlacePrediction,
  RouteResult,
} from './geo-provider.interface';

/**
 * Composes a primary provider (e.g. Google) with a secondary (e.g. self-hosted
 * OSRM/Nominatim): every call tries the primary and, on any error, transparently
 * falls back to the secondary. This means a Google outage, quota exhaustion, or a
 * not-yet-enabled API can never take geo down — the app keeps serving on OSM.
 *
 * Caveat: place ids are provider-specific. `placeDetails` only falls back to the
 * secondary if the primary throws; a Google place id resolved by the secondary
 * would not match, so in practice place lookups stay within whichever provider
 * produced the id. Route/reverse/autocomplete are stateless (coords or free text)
 * and fall back cleanly.
 */
export class FallbackGeoProvider implements GeoProvider {
  private readonly logger = new Logger('FallbackGeo');

  constructor(
    private readonly primary: GeoProvider,
    private readonly secondary: GeoProvider,
  ) {}

  private async withFallback<T>(
    op: string,
    primary: () => Promise<T>,
    secondary: () => Promise<T>,
  ): Promise<T> {
    try {
      return await primary();
    } catch (e) {
      this.logger.warn(
        `primary ${op} failed (${(e as Error).message}); using secondary`,
      );
      return secondary();
    }
  }

  autocomplete(
    query: string,
    sessionToken?: string,
    bias?: LatLng,
  ): Promise<PlacePrediction[]> {
    return this.withFallback(
      'autocomplete',
      () => this.primary.autocomplete(query, sessionToken, bias),
      () => this.secondary.autocomplete(query, sessionToken, bias),
    );
  }

  placeDetails(placeId: string): Promise<PlaceDetails> {
    return this.withFallback(
      'placeDetails',
      () => this.primary.placeDetails(placeId),
      () => this.secondary.placeDetails(placeId),
    );
  }

  reverse(location: LatLng): Promise<PlaceDetails> {
    return this.withFallback(
      'reverse',
      () => this.primary.reverse(location),
      () => this.secondary.reverse(location),
    );
  }

  route(origin: LatLng, destination: LatLng): Promise<RouteResult> {
    return this.withFallback(
      'route',
      () => this.primary.route(origin, destination),
      () => this.secondary.route(origin, destination),
    );
  }
}
