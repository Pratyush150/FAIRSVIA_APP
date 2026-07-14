import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthUser } from '../auth/strategies/jwt.strategy';
import { SafetyService } from './safety.service';
import { SosDto } from './dto/sos.dto';

@Controller()
@UseGuards(JwtAuthGuard)
export class SafetyController {
  constructor(private readonly safety: SafetyService) {}

  @Post('trips/:tripId/sos')
  sos(
    @CurrentUser() user: AuthUser,
    @Param('tripId', ParseUUIDPipe) tripId: string,
    @Body() dto: SosDto,
  ) {
    return this.safety.raiseSos(user.userId, tripId, dto);
  }

  @Get('admin/safety')
  @UseGuards(RolesGuard)
  @Roles(UserRole.admin)
  recent(@Query('limit') limit?: string) {
    return this.safety.recentSos(limit ? parseInt(limit, 10) : undefined);
  }
}
