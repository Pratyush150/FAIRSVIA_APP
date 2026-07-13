import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import {
  GeoProvider,
  LatLng,
  PlaceDetails,
  PlacePrediction,
  RouteResult,
} from './geo-provider.interface';
import { encodePolyline, haversineMeters } from './geo.util';

/**
 * Deterministic stand-in for Google Maps used when no API key is set.
 * Coordinates are encoded into the placeId so placeDetails round-trips.
 * Routes are straight lines at an assumed average city speed.
 */
@Injectable()
export class StubGeoProvider implements GeoProvider {
  private readonly logger = new Logger('StubGeo');

  // City center used as the origin for generated predictions (Bengaluru).
  private static readonly base: LatLng = { lat: 12.9716, lng: 77.5946 };
  private static readonly avgSpeedMps = 8.33; // ~30 km/h

  constructor() {
    this.logger.warn(
      'Using STUB geo provider (no GOOGLE_MAPS_API_KEY). Set the key for real maps.',
    );
  }

  async autocomplete(query: string): Promise<PlacePrediction[]> {
    const suffixes = ['Road', 'Metro Station', 'Mall', 'Park'];
    return suffixes.map((suffix, i) => {
      const loc = this.offset(StubGeoProvider.base, query, i);
      const primary = `${query} ${suffix}`.trim();
      return {
        placeId: this.encodePlaceId(loc),
        primaryText: primary,
        secondaryText: 'Bengaluru, Karnataka',
        description: `${primary}, Bengaluru, Karnataka`,
      };
    });
  }

  async placeDetails(placeId: string): Promise<PlaceDetails> {
    const loc = this.decodePlaceId(placeId);
    if (!loc) {
      throw new NotFoundException('Unknown placeId');
    }
    return {
      placeId,
      address: `Stub location (${loc.lat.toFixed(5)}, ${loc.lng.toFixed(5)})`,
      location: loc,
    };
  }

  async route(origin: LatLng, destination: LatLng): Promise<RouteResult> {
    const straight = haversineMeters(origin, destination);
    // Roads aren't straight; apply a modest detour factor.
    const distanceM = Math.round(straight * 1.3);
    const durationS = Math.max(
      60,
      Math.round(distanceM / StubGeoProvider.avgSpeedMps),
    );
    return {
      distanceM,
      durationS,
      polyline: encodePolyline([origin, destination]),
    };
  }

  private offset(base: LatLng, seed: string, index: number): LatLng {
    let hash = 0;
    for (let i = 0; i < seed.length; i++) {
      hash = (hash * 31 + seed.charCodeAt(i)) & 0xffff;
    }
    const jitter = ((hash % 200) - 100) / 10000; // ~±0.01 deg
    return {
      lat: base.lat + jitter + index * 0.004,
      lng: base.lng + jitter - index * 0.003,
    };
  }

  private encodePlaceId(loc: LatLng): string {
    return `stub:${loc.lat.toFixed(6)},${loc.lng.toFixed(6)}`;
  }

  private decodePlaceId(placeId: string): LatLng | null {
    if (!placeId.startsWith('stub:')) return null;
    const [lat, lng] = placeId.slice(5).split(',').map(Number);
    if (Number.isNaN(lat) || Number.isNaN(lng)) return null;
    return { lat, lng };
  }
}
