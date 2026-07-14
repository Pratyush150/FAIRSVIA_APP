import { BadGatewayException, Logger, NotFoundException } from '@nestjs/common';
import {
  GeoProvider,
  LatLng,
  PlaceDetails,
  PlacePrediction,
  RouteResult,
} from './geo-provider.interface';

/**
 * Self-hostable OpenStreetMap provider: OSRM for road-following routes and
 * Nominatim for place search / geocoding. Both base URLs are configurable so
 * they can point at the docker-compose services (default) or the public OSM
 * demo servers. No API key required.
 *
 * Selected in GeoModule when OSRM_BASE_URL + NOMINATIM_BASE_URL are set (and no
 * Google key is configured). OSRM's `geometries=polyline` returns a precision-5
 * Google-encoded polyline — the same format the rider app already decodes.
 */
export class OsmGeoProvider implements GeoProvider {
  private readonly logger = new Logger('OsmGeo');

  // Bias search ordering toward the Miami metro without hard-bounding results
  // (the Florida extract is statewide). Order: left,top,right,bottom (lon,lat).
  private static readonly miamiViewbox = '-80.45,25.95,-80.10,25.55';
  private static readonly userAgent = 'UberNav/1.0 (self-hosted)';

  constructor(
    private readonly osrmBaseUrl: string,
    private readonly nominatimBaseUrl: string,
  ) {
    this.osrmBaseUrl = osrmBaseUrl.replace(/\/+$/, '');
    this.nominatimBaseUrl = nominatimBaseUrl.replace(/\/+$/, '');
  }

  async autocomplete(query: string): Promise<PlacePrediction[]> {
    const url = new URL(`${this.nominatimBaseUrl}/search`);
    url.searchParams.set('q', query);
    url.searchParams.set('format', 'jsonv2');
    url.searchParams.set('addressdetails', '1');
    url.searchParams.set('limit', '6');
    url.searchParams.set('countrycodes', 'us');
    url.searchParams.set('viewbox', OsmGeoProvider.miamiViewbox);

    const data = (await this.getJson(url)) as any[];
    return (data ?? []).map((r) => {
      const location: LatLng = { lat: Number(r.lat), lng: Number(r.lon) };
      const display = String(r.display_name ?? '');
      const primary = String(r.name && r.name.length > 0 ? r.name : display.split(',')[0]);
      const secondary = display.startsWith(primary)
        ? display.slice(primary.length).replace(/^,\s*/, '')
        : display;
      return {
        placeId: this.encodePlaceId(location, display),
        primaryText: primary,
        secondaryText: secondary,
        description: display,
      };
    });
  }

  async placeDetails(placeId: string): Promise<PlaceDetails> {
    const decoded = this.decodePlaceId(placeId);
    if (!decoded) throw new NotFoundException('Unknown placeId');
    return {
      placeId,
      address: decoded.address,
      location: decoded.location,
    };
  }

  async route(origin: LatLng, destination: LatLng): Promise<RouteResult> {
    const coords = `${origin.lng},${origin.lat};${destination.lng},${destination.lat}`;
    const url = new URL(`${this.osrmBaseUrl}/route/v1/driving/${coords}`);
    url.searchParams.set('overview', 'full');
    url.searchParams.set('geometries', 'polyline');

    const data = await this.getJson(url);
    if (data.code !== 'Ok' || !(data.routes ?? [])[0]) {
      throw new BadGatewayException(`No route found (${data.code ?? 'unknown'})`);
    }
    const route = data.routes[0];
    return {
      distanceM: Math.round(route.distance as number),
      durationS: Math.round(route.duration as number),
      polyline: route.geometry as string,
    };
  }

  /** Encode the resolved location + address so placeDetails needs no 2nd call. */
  private encodePlaceId(location: LatLng, address: string): string {
    const blob = JSON.stringify({ lat: location.lat, lng: location.lng, address });
    return `osm:${Buffer.from(blob, 'utf8').toString('base64url')}`;
  }

  private decodePlaceId(
    placeId: string,
  ): { location: LatLng; address: string } | null {
    if (!placeId.startsWith('osm:')) return null;
    try {
      const json = Buffer.from(placeId.slice(4), 'base64url').toString('utf8');
      const parsed = JSON.parse(json);
      const lat = Number(parsed.lat);
      const lng = Number(parsed.lng);
      if (Number.isNaN(lat) || Number.isNaN(lng)) return null;
      return { location: { lat, lng }, address: String(parsed.address ?? '') };
    } catch {
      return null;
    }
  }

  private async getJson(url: URL): Promise<any> {
    let res: Response;
    try {
      res = await fetch(url, {
        headers: { 'User-Agent': OsmGeoProvider.userAgent },
      });
    } catch (e) {
      this.logger.error(`OSM request failed: ${(e as Error).message}`);
      throw new BadGatewayException('Maps provider unreachable');
    }
    if (!res.ok) {
      throw new BadGatewayException(`Maps provider error: ${res.status}`);
    }
    return res.json();
  }
}
