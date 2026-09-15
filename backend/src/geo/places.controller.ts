import {
  BadRequestException,
  Controller,
  Get,
  Inject,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { GEO_PROVIDER, GeoProvider, LatLng } from './geo-provider.interface';

/**
 * Proxies Google Places through the backend so the API key stays server-side,
 * calls can be cached/rate-limited, and clients never see it.
 */
@Controller('places')
@UseGuards(JwtAuthGuard)
export class PlacesController {
  constructor(@Inject(GEO_PROVIDER) private readonly geo: GeoProvider) {}

  /**
   * Place search. Optional `lat`/`lng` (the rider's position) bias results to
   * ~20 km around them and add `distanceM` per prediction where the provider
   * reports it. Invalid/partial coordinates are ignored, not an error.
   */
  @Get('autocomplete')
  autocomplete(
    @Query('q') q: string,
    @Query('sessionToken') sessionToken?: string,
    @Query('lat') lat?: string,
    @Query('lng') lng?: string,
  ) {
    if (!q || q.trim().length < 2) {
      return { predictions: [] };
    }
    const bias = PlacesController.parseBias(lat, lng);
    return this.geo
      .autocomplete(q.trim(), sessionToken, bias)
      .then((predictions) => ({ predictions }));
  }

  /** Valid lat/lng pair → bias point; anything else → undefined. */
  static parseBias(lat?: string, lng?: string): LatLng | undefined {
    if (lat === undefined || lng === undefined || lat === '' || lng === '') {
      return undefined;
    }
    const latN = Number(lat);
    const lngN = Number(lng);
    if (!Number.isFinite(latN) || !Number.isFinite(lngN)) return undefined;
    if (Math.abs(latN) > 90 || Math.abs(lngN) > 180) return undefined;
    return { lat: latN, lng: lngN };
  }

  @Get('details')
  details(@Query('placeId') placeId: string) {
    return this.geo.placeDetails(placeId);
  }

  /** Reverse-geocode the rider's GPS to a human address for the pickup label. */
  @Get('reverse')
  reverse(@Query('lat') lat: string, @Query('lng') lng: string) {
    const latN = Number(lat);
    const lngN = Number(lng);
    if (Number.isNaN(latN) || Number.isNaN(lngN)) {
      return { address: 'Current location', location: { lat: latN, lng: lngN } };
    }
    return this.geo.reverse({ lat: latN, lng: lngN });
  }

  /**
   * On-demand road route between two points. Used for **live re-routing**: when
   * a driver deviates from the planned path, the app re-fetches the optimal
   * route from the car's current position to its target (pickup, then dropoff)
   * so the drawn line follows the road actually taken. Read-only.
   */
  @Get('route')
  route(
    @Query('fromLat') fromLat: string,
    @Query('fromLng') fromLng: string,
    @Query('toLat') toLat: string,
    @Query('toLng') toLng: string,
  ) {
    // Parse each param, treating empty/whitespace as missing (Number('') is 0,
    // which would otherwise pass as a valid — but wrong — coordinate).
    const nums = [fromLat, fromLng, toLat, toLng].map((s) =>
      s == null || s.trim() === '' ? NaN : Number(s),
    );
    if (nums.some((n) => Number.isNaN(n))) {
      throw new BadRequestException(
        'fromLat, fromLng, toLat and toLng must all be numbers',
      );
    }
    const [oLat, oLng, dLat, dLng] = nums;
    return this.geo.route(
      { lat: oLat, lng: oLng },
      { lat: dLat, lng: dLng },
    );
  }
}
