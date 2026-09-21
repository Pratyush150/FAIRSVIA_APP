import {
  GeoProvider,
  LatLng,
  PlaceDetails,
  PlacePrediction,
  RouteResult,
} from './geo-provider.interface';
import { MetricsService } from '../common/metrics/metrics.service';

/**
 * Wraps a [GeoProvider] and times every call into
 * `vendor_request_duration_seconds{vendor,operation,status}`.
 *
 * A decorator rather than instrumentation inside each provider: it applies
 * identically to Google, OSRM/Nominatim and the stub, and it composes with
 * [FallbackGeoProvider] so the primary and the secondary are measured
 * separately. That separation is the point — a Google quota wall shows up as
 * `vendor="google",status="error"` climbing while `vendor="osm"` picks up the
 * traffic, which is exactly the shape of the 20,370 OVER_QUERY_LIMIT errors
 * that went unnoticed for hours during the load sweep.
 *
 * Errors are re-thrown untouched; this only observes.
 */
export class InstrumentedGeoProvider implements GeoProvider {
  constructor(
    private readonly inner: GeoProvider,
    private readonly vendor: string,
    private readonly metrics: MetricsService,
  ) {}

  private async timed<T>(operation: string, fn: () => Promise<T>): Promise<T> {
    const start = Date.now();
    try {
      const out = await fn();
      this.metrics.observeVendor(this.vendor, operation, true, Date.now() - start);
      return out;
    } catch (e) {
      this.metrics.observeVendor(
        this.vendor,
        operation,
        false,
        Date.now() - start,
      );
      throw e;
    }
  }

  autocomplete(
    query: string,
    sessionToken?: string,
    bias?: LatLng,
  ): Promise<PlacePrediction[]> {
    return this.timed('autocomplete', () =>
      this.inner.autocomplete(query, sessionToken, bias),
    );
  }

  placeDetails(placeId: string): Promise<PlaceDetails> {
    return this.timed('placeDetails', () => this.inner.placeDetails(placeId));
  }

  reverse(location: LatLng): Promise<PlaceDetails> {
    return this.timed('reverse', () => this.inner.reverse(location));
  }

  route(origin: LatLng, destination: LatLng): Promise<RouteResult> {
    return this.timed('route', () => this.inner.route(origin, destination));
  }
}
