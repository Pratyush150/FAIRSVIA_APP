import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthUser } from '../auth/strategies/jwt.strategy';
import { DriversService } from './drivers.service';
import { OnboardingDto } from './dto/onboarding.dto';
import { DriverStatusDto } from './dto/status.dto';
import { DemandQueryDto } from './dto/demand.dto';
import { DemandMapService } from './demand-map.service';

@Controller('drivers')
@UseGuards(JwtAuthGuard)
export class DriversController {
  constructor(
    private readonly drivers: DriversService,
    private readonly demand: DemandMapService,
  ) {}

  @Post('onboarding')
  onboarding(@CurrentUser() user: AuthUser, @Body() dto: OnboardingDto) {
    return this.drivers.onboarding(user.userId, dto);
  }

  @Get('me')
  me(@CurrentUser() user: AuthUser) {
    return this.drivers.getProfileWithPresence(user.userId);
  }

  @Post('status')
  @HttpCode(HttpStatus.OK)
  status(@CurrentUser() user: AuthUser, @Body() dto: DriverStatusDto) {
    return this.drivers.setStatus(user.userId, dto.status);
  }

  @Get('me/earnings')
  earnings(
    @CurrentUser() user: AuthUser,
    @Query('range') range?: string,
  ) {
    return this.drivers.earnings(
      user.userId,
      range === 'week' ? 'week' : 'today',
    );
  }

  /** "Busy areas": recent ride requests on a ~1 km grid around a point.
   *  Drivers only — it is a supply-positioning aid, not rider data. */
  @Get('me/demand')
  async demandMap(@CurrentUser() user: AuthUser, @Query() q: DemandQueryDto) {
    await this.drivers.getProfile(user.userId);
    return this.demand.around(q.lat, q.lng);
  }
}
