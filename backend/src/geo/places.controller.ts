import {
  Controller,
  Get,
  Inject,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { GEO_PROVIDER, GeoProvider } from './geo-provider.interface';

/**
 * Proxies Google Places through the backend so the API key stays server-side,
 * calls can be cached/rate-limited, and clients never see it.
 */
@Controller('places')
@UseGuards(JwtAuthGuard)
export class PlacesController {
  constructor(@Inject(GEO_PROVIDER) private readonly geo: GeoProvider) {}

  @Get('autocomplete')
  autocomplete(
    @Query('q') q: string,
    @Query('sessionToken') sessionToken?: string,
  ) {
    if (!q || q.trim().length < 2) {
      return { predictions: [] };
    }
    return this.geo
      .autocomplete(q.trim(), sessionToken)
      .then((predictions) => ({ predictions }));
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
}
