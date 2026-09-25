import { Controller, Get, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthUser } from '../auth/strategies/jwt.strategy';
import { DriverStatsService } from './driver-stats.service';
import { QuestsService } from './quests.service';

/** Driver-facing incentives: acceptance/cancellation rates and quests. */
@Controller('drivers/me')
@UseGuards(JwtAuthGuard)
export class IncentivesController {
  constructor(
    private readonly stats: DriverStatsService,
    private readonly quests: QuestsService,
  ) {}

  @Get('stats')
  myStats(@CurrentUser() user: AuthUser) {
    return this.stats.stats(user.userId);
  }

  @Get('quests')
  myQuests(@CurrentUser() user: AuthUser) {
    return this.quests.forDriver(user.userId);
  }
}
