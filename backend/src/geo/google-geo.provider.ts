import { BadGatewayException, Logger } from '@nestjs/common';
import {
  GeoProvider,
  LatLng,
  PlaceDetails,
  PlacePrediction,
  RouteResult,
} from './geo-provider.interface';

/**
 * Real Google Maps Platform provider. Requires GOOGLE_MAPS_API_KEY with
 * Places, Directions, and Geocoding enabled. Called server-side so the key is
 * never exposed to clients.
 */
export class GoogleGeoProvider implements GeoProvider {
  private readonly logger = new Logger('GoogleGeo');
  private static readonly base = 'https://maps.googleapis.com/maps/api';

  constructor(private readonly apiKey: string) {}

  async autocomplete(
    query: string,
    sessionToken?: string,
  ): Promise<PlacePrediction[]> {
    const url = new URL(`${GoogleGeoProvider.base}/place/autocomplete/json`);
    url.searchParams.set('input', query);
    url.searchParams.set('key', this.apiKey);
    if (sessionToken) url.searchParams.set('sessiontoken', sessionToken);

    const data = await this.getJson(url);
    const predictions = (data.predictions ?? []) as any[];
    return predictions.map((p) => ({
      placeId: p.place_id as string,
      primaryText: p.structured_formatting?.main_text ?? p.description,
      secondaryText: p.structured_formatting?.secondary_text ?? '',
      description: p.description as string,
    }));
  }

  async placeDetails(placeId: string): Promise<PlaceDetails> {
    const url = new URL(`${GoogleGeoProvider.base}/place/details/json`);
    url.searchParams.set('place_id', placeId);
    url.searchParams.set('fields', 'formatted_address,geometry');
    url.searchParams.set('key', this.apiKey);

    const data = await this.getJson(url);
    const result = data.result;
    if (!result) throw new BadGatewayException('Place details unavailable');
    return {
      placeId,
      address: result.formatted_address as string,
      location: {
        lat: result.geometry.location.lat as number,
        lng: result.geometry.location.lng as number,
      },
    };
  }

  async reverse(location: LatLng): Promise<PlaceDetails> {
    const url = new URL(`${GoogleGeoProvider.base}/geocode/json`);
    url.searchParams.set('latlng', `${location.lat},${location.lng}`);
    url.searchParams.set('key', this.apiKey);

    const data = await this.getJson(url);
    const result = (data.results ?? [])[0];
    const address = result?.formatted_address ?? 'Current location';
    return {
      placeId: result?.place_id ?? `latlng:${location.lat},${location.lng}`,
      address,
      location,
    };
  }

  async route(origin: LatLng, destination: LatLng): Promise<RouteResult> {
    const url = new URL(`${GoogleGeoProvider.base}/directions/json`);
    url.searchParams.set('origin', `${origin.lat},${origin.lng}`);
    url.searchParams.set('destination', `${destination.lat},${destination.lng}`);
    url.searchParams.set('key', this.apiKey);

    const data = await this.getJson(url);
    const route = (data.routes ?? [])[0];
    if (!route) throw new BadGatewayException('No route found');
    const leg = route.legs[0];
    return {
      distanceM: leg.distance.value as number,
      durationS: leg.duration.value as number,
      polyline: route.overview_polyline.points as string,
    };
  }

  private async getJson(url: URL): Promise<any> {
    let res: Response;
    try {
      res = await fetch(url);
    } catch (e) {
      this.logger.error(`Google Maps request failed: ${(e as Error).message}`);
      throw new BadGatewayException('Maps provider unreachable');
    }
    if (!res.ok) {
      throw new BadGatewayException(`Maps provider error: ${res.status}`);
    }
    const data = await res.json();
    // Google returns 200 with a status field for API-level errors.
    if (data.status && data.status !== 'OK' && data.status !== 'ZERO_RESULTS') {
      this.logger.error(`Google Maps status ${data.status}: ${data.error_message ?? ''}`);
      throw new BadGatewayException(`Maps provider: ${data.status}`);
    }
    return data;
  }
}
