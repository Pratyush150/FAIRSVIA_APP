import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Inject,
  Post,
  UseGuards,
} from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import {
  GEO_PROVIDER,
  GeoProvider,
  LatLng,
} from '../geo/geo-provider.interface';
import { SurgeService } from '../surge/surge.service';
import { ComparisonService } from './comparison.service';
import { CalibrationService } from './calibration.service';
import { CompareDto } from './dto/compare.dto';
import { RecordSampleDto } from './dto/record-sample.dto';

/**
 * Price-comparison API: given a pickup/dropoff, return our fare alongside
 * the market's modeled competitor fares for the same trip, with the cheapest
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
    private readonly calibration: CalibrationService,
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
      undefined,
      dto.currency,
    );
  }

  /**
   * Admin: record an observed real competitor fare to calibrate that provider's
   * rate card. Gathered manually / from a small consented panel — never scraped.
   * Triggers a re-fit once enough samples exist.
   */
  @Post('samples')
  @UseGuards(RolesGuard)
  @Roles(UserRole.admin)
  @HttpCode(HttpStatus.OK)
  async recordSample(@Body() dto: RecordSampleDto) {
    return this.calibration.recordSample(dto);
  }

  /** Admin: current (possibly calibrated) competitor models + fit provenance. */
  @Get('models')
  @UseGuards(RolesGuard)
  @Roles(UserRole.admin)
  models() {
    return this.calibration.models();
  }
}
