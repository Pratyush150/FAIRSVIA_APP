export const GEO_PROVIDER = 'GEO_PROVIDER';

export interface LatLng {
  lat: number;
  lng: number;
}

export interface PlacePrediction {
  placeId: string;
  primaryText: string;
  secondaryText: string;
  description: string;
}

export interface PlaceDetails {
  placeId: string;
  address: string;
  location: LatLng;
}

export interface RouteResult {
  distanceM: number;
  durationS: number;
  /// Google-encoded polyline of the route.
  polyline: string;
}

/**
 * Abstraction over the maps provider. The real implementation calls Google
 * Maps Platform; the stub returns deterministic data so the whole ride flow
 * is testable without an API key. Selected in GeoModule by whether
 * GOOGLE_MAPS_API_KEY is configured.
 */
export interface GeoProvider {
  autocomplete(query: string, sessionToken?: string): Promise<PlacePrediction[]>;
  placeDetails(placeId: string): Promise<PlaceDetails>;
  /** Resolve raw coordinates (e.g. the rider's GPS) to a human address. */
  reverse(location: LatLng): Promise<PlaceDetails>;
  route(origin: LatLng, destination: LatLng): Promise<RouteResult>;
}
