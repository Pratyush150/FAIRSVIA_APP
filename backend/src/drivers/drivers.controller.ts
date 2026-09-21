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

@Controller('drivers')
@UseGuards(JwtAuthGuard)
export class DriversController {
  constructor(private readonly drivers: DriversService) {}

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
}
