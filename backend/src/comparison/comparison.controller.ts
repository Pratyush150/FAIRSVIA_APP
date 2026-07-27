import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Inject,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import {
  GEO_PROVIDER,
  GeoProvider,
  LatLng,
} from '../geo/geo-provider.interface';
import { SurgeService } from '../surge/surge.service';
import { ComparisonService } from './comparison.service';
import { CompareDto } from './dto/compare.dto';

/**
 * Price-comparison API: given a pickup/dropoff, return our fare alongside
 * modeled Uber / Lyft / Empower fares for the same trip, with the cheapest
 * (minimum-price) provider flagged. See competitor-config.ts for the honesty
 * note on why competitor prices are modeled, not live.
 */
@Controller('comparison')
@UseGuards(JwtAuthGuard)
export class ComparisonController {
  constructor(
    @Inject(GEO_PROVIDER) private readonly geo: GeoProvider,
    private readonly surge: SurgeService,
    private readonly comparison: ComparisonService,
  ) {}

  @Post('estimate')
  @HttpCode(HttpStatus.OK)
  async estimate(@Body() dto: CompareDto) {
    const pickup: LatLng = { lat: dto.pickupLat, lng: dto.pickupLng };
    const dropoff: LatLng = { lat: dto.dropoffLat, lng: dto.dropoffLng };

    // Route pickup → stops… → dropoff, summing distance/time.
    const points: LatLng[] = [
      pickup,
      ...(dto.stops ?? []).map((s) => ({ lat: s.lat, lng: s.lng })),
      dropoff,
    ];
    let distanceM = 0;
    let durationS = 0;
    for (let i = 0; i < points.length - 1; i++) {
      const leg = await this.geo.route(points[i], points[i + 1]);
      distanceM += leg.distanceM;
      durationS += leg.durationS;
    }

    const surge = await this.surge.multiplierFor(pickup.lat, pickup.lng);
    return this.comparison.compare(
      distanceM,
      durationS,
      surge,
      dto.tier ?? 'economy',
    );
  }
}
