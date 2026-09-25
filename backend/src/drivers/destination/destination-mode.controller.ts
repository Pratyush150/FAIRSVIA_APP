import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../../auth/decorators/current-user.decorator';
import { AuthUser } from '../../auth/strategies/jwt.strategy';
import { DestinationModeService } from './destination-mode.service';
import { DestinationModeDto } from './destination.dto';

/** Destination ("go home") mode — see destination.rules.ts for the rule. */
@Controller('drivers/me/destination-mode')
@UseGuards(JwtAuthGuard)
export class DestinationModeController {
  constructor(private readonly destination: DestinationModeService) {}

  @Get()
  get(@CurrentUser() user: AuthUser) {
    return this.destination.get(user.userId);
  }

  @Post()
  @HttpCode(HttpStatus.OK)
  set(@CurrentUser() user: AuthUser, @Body() dto: DestinationModeDto) {
    return this.destination.set(user.userId, dto);
  }

  @Delete()
  @HttpCode(HttpStatus.OK)
  clear(@CurrentUser() user: AuthUser) {
    return this.destination.clear(user.userId);
  }
}
