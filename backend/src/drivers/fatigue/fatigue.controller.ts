import { Controller, Get, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../../auth/decorators/current-user.decorator';
import { AuthUser } from '../../auth/strategies/jwt.strategy';
import { FatigueService } from './fatigue.service';

@Controller('drivers')
@UseGuards(JwtAuthGuard)
export class FatigueController {
  constructor(private readonly fatigue: FatigueService) {}

  /** "Online today: 9h 40m of 12h" + the rest countdown when locked out. */
  @Get('me/fatigue')
  status(@CurrentUser() user: AuthUser) {
    return this.fatigue.state(user.userId);
  }
}
